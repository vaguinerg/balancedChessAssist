import raylib
import types
import stockfish
import math
import random
import times

var gameState = GameState(pieces: @[], flipped: false)
var pendingPromotion: Piece = nil

# Configurações de humanização
type
  HumanizationConfig = object
    thinkingTimeMin: float      # Tempo mínimo para "pensar"
    thinkingTimeMax: float      # Tempo máximo para "pensar"
    blunderChance: float        # Chance de cometer erro (0.0-1.0)
    inaccuracyFactor: float     # Fator de imprecisão (0.0-1.0)
    preferComplexity: float     # Preferência por jogadas mais complexas
    openingBookDepth: int       # Profundidade do livro de aberturas
    endgameAccuracy: float      # Precisão no final do jogo

var humanConfig = HumanizationConfig(
  thinkingTimeMin: 1.0,
  thinkingTimeMax: 8.0,
  blunderChance: 0.08,         # 8% de chance de erro
  inaccuracyFactor: 0.15,      # 15% de imprecisão
  preferComplexity: 0.3,       # 30% de preferência por complexidade
  openingBookDepth: 12,
  endgameAccuracy: 0.85        # 85% de precisão no endgame
)

# Variáveis para controle temporal
var lastMoveTime: float = 0.0
var isThinking: bool = false
var thinkingStartTime: float = 0.0
var plannedThinkingTime: float = 0.0

proc getCurrentTime(): float =
  return float(epochTime())

proc initializeGame*() =
  gameState.pieces = @[]
  gameState.flipped = false
  gameState.currentTurn = White
  gameState.lastEvaluation = 0.0
  gameState.suggestedMoves = @[]
  gameState.promotionButtons = @[]
  lastMoveTime = getCurrentTime()
  isThinking = false
  
  # Setup inicial das peças
  let pieceSetup = [
    (Rook, 0), (Knight, 1), (Bishop, 2), (Queen, 3),
    (King, 4), (Bishop, 5), (Knight, 6), (Rook, 7)
  ]
  
  for (kind, x) in pieceSetup:
    gameState.pieces.add(Piece(kind: kind, color: Dark, x: x, y: 0))
    gameState.pieces.add(Piece(kind: kind, color: White, x: x, y: 7))
    
  for x in 0..7:
    gameState.pieces.add(Piece(kind: Pawn, color: Dark, x: x, y: 1))
    gameState.pieces.add(Piece(kind: Pawn, color: White, x: x, y: 6))

proc findPieceAt(x, y: int): Piece =
  for piece in gameState.pieces:
    if piece.x == x and piece.y == y:
      return piece
  return nil

proc getGamePhase(): float =
  # Determina a fase do jogo baseado no material restante
  var materialCount = 0
  for piece in gameState.pieces:
    case piece.kind:
    of Queen: materialCount += 9
    of Rook: materialCount += 5
    of Bishop, Knight: materialCount += 3
    of Pawn: materialCount += 1
    of King: discard
  
  # 0.0 = opening, 0.5 = middlegame, 1.0 = endgame
  let maxMaterial = 78 # Material inicial (sem reis)
  return 1.0 - (float(materialCount) / float(maxMaterial))

proc calculateMoveComplexity(move: StockfishMove): float =
  # Calcular complexidade baseada em vários fatores
  var complexity = 0.0
  
  let movingPiece = findPieceAt(move.fromX, move.fromY)
  if movingPiece != nil:
    # Movimentos de peças menores são mais "humanos"
    case movingPiece.kind:
    of Pawn: complexity += 0.1
    of Knight: complexity += 0.3
    of Bishop: complexity += 0.2
    of Rook: complexity += 0.2
    of Queen: complexity += 0.4
    of King: complexity += 0.1
  
  # Movimentos para o centro são preferidos por humanos
  let centerDistance = abs(move.toX.float64 - 3.5) + abs(move.toY.float64 - 3.5)
  complexity += (7.0 - centerDistance) * 0.05
  
  # Capturas são mais óbvias (menor complexidade para humanos)
  let targetPiece = findPieceAt(move.toX, move.toY)
  if targetPiece != nil:
    complexity -= 0.2
  
  return complexity

proc addHumanError(score: float, gamePhase: float): float =
  # Adiciona erro humano baseado na fase do jogo
  let errorMagnitude = humanConfig.inaccuracyFactor * (1.0 - gamePhase * humanConfig.endgameAccuracy)
  let randomError = (rand(2.0) - 1.0) * errorMagnitude * abs(score)
  return score + randomError

proc shouldBlunder(gamePhase: float): bool =
  # Chance de blunder reduzida no endgame
  let adjustedChance = humanConfig.blunderChance * (1.0 - gamePhase * 0.5)
  return rand(1.0) < adjustedChance

proc getHumanizedMove(): StockfishMove =
  if gameState.suggestedMoves.len == 0:
    return StockfishMove()
  
  let gamePhase = getGamePhase()
  
  # Verificar se deve cometer um blunder
  if shouldBlunder(gamePhase) and gameState.suggestedMoves.len > 3:
    echo "=== BLUNDER INTENCIONAL ==="
    # Escolher um movimento entre os 30% piores, mas não o pior absoluto
    let worstIndex = max(2, int(float(gameState.suggestedMoves.len) * 0.7))
    let blunderMove = gameState.suggestedMoves[rand(worstIndex..<gameState.suggestedMoves.len)]
    echo "Escolhendo blunder: posição ", worstIndex, " de ", gameState.suggestedMoves.len
    return blunderMove
  
  # Análise normal com fatores humanos
  var bestMove: StockfishMove
  var bestScore: float = -999999.0
  
  # Limitar análise aos top 5 movimentos (comportamento mais humano)
  let analysisDepth = min(5, gameState.suggestedMoves.len)
  
  for i in 0..<analysisDepth:
    let move = gameState.suggestedMoves[i]
    
    # Score base com erro humano
    var humanScore = addHumanError(move.score, gamePhase)
    
    # Fator de complexidade
    let complexity = calculateMoveComplexity(move)
    let complexityBonus = complexity * humanConfig.preferComplexity * (1.0 - gamePhase)
    humanScore += complexityBonus
    
    # Penalizar ligeiramente movimentos muito óbvios (rank 0)
    if i == 0:
      humanScore -= 0.1
    
    # Bonus aleatório pequeno para simular "intuição"
    let intuitionBonus = (rand(0.3) - 0.15)
    humanScore += intuitionBonus
    
    echo "Move ", i+1, ": score=", move.score, " humanScore=", humanScore, " complexity=", complexity
    
    if humanScore > bestScore:
      bestScore = humanScore
      bestMove = move
  
  echo "=== MOVIMENTO HUMANIZADO ESCOLHIDO ==="
  echo "De: (", bestMove.fromX, ",", bestMove.fromY, ") Para: (", bestMove.toX, ",", bestMove.toY, ")"
  echo "Score original: ", bestMove.score
  echo "Fase do jogo: ", gamePhase
  
  return bestMove

proc startThinking() =
  isThinking = true
  thinkingStartTime = getCurrentTime()
  
  # Tempo de pensamento baseado na complexidade da posição
  let gamePhase = getGamePhase()
  let baseTime = humanConfig.thinkingTimeMin + 
                (humanConfig.thinkingTimeMax - humanConfig.thinkingTimeMin) * gamePhase
  
  # Adicionar variação aleatória
  let timeVariation = rand(2.0) - 1.0  # -1 a +1
  plannedThinkingTime = baseTime + timeVariation
  
  # Garantir limites
  plannedThinkingTime = max(humanConfig.thinkingTimeMin, 
                           min(humanConfig.thinkingTimeMax, plannedThinkingTime))
  
  echo "Iniciando período de reflexão: ", plannedThinkingTime, " segundos"

proc isThinkingComplete(): bool =
  if not isThinking:
    return true
  
  let elapsedTime = getCurrentTime() - thinkingStartTime
  return elapsedTime >= plannedThinkingTime

proc finishThinking() =
  isThinking = false
  echo "Período de reflexão concluído"

# [Resto das funções permanecem iguais: getAdjustedGridPosition, findPieceAt, etc.]

proc getAdjustedGridPosition(mousePos: Vector2, squareSize: Vector2): tuple[x, y: int] =
  let rawX = int(mousePos.x / squareSize.x)
  let rawY = int(mousePos.y / squareSize.y)
  
  if gameState.flipped:
    result = (x: 7 - rawX, y: 7 - rawY)
  else:
    result = (x: rawX, y: rawY)

proc findPieceIndex(piece: Piece): int =
  for i in 0..<gameState.pieces.len:
    if gameState.pieces[i] == piece:
      return i
  return -1

proc createPromotionButtons(piece: Piece) =
  gameState.promotionButtons = @[]
  let squareSize = float(getScreenWidth()) / 8.0
  let options = [Queen, Rook, Bishop, Knight]
  
  for i, kind in options:
    gameState.promotionButtons.add(PromotionButton(
      rect: Rectangle(
        x: squareSize * float(i + 2), 
        y: float(getScreenHeight()) / 2 - squareSize / 2,
        width: squareSize,
        height: squareSize
      ),
      kind: kind
    ))

proc isValidCastling(king: Piece, fromX, fromY, toX, toY: int): bool =
  if abs(toX - fromX) != 2 or toY != fromY:
    return false
  
  let isKingside = toX > fromX
  let rookX = if isKingside: 7 else: 0
  let rookNewX = if isKingside: toX - 1 else: toX + 1
  
  let rook = findPieceAt(rookX, fromY)
  if rook == nil or rook.kind != Rook or rook.color != king.color:
    return false
  
  let startX = min(fromX, rookX) + 1
  let endX = max(fromX, rookX) - 1
  
  for x in startX..endX:
    if findPieceAt(x, fromY) != nil:
      return false
  
  return true

proc executeCastling(king: Piece, toX: int) =
  let isKingside = toX > king.x
  let rookX = if isKingside: 7 else: 0
  let rookNewX = if isKingside: toX - 1 else: toX + 1
  
  let rook = findPieceAt(rookX, king.y)
  if rook != nil:
    rook.x = rookNewX

proc isValidMove(piece: Piece, fromX, fromY, toX, toY: int): bool =
  if toX < 0 or toX > 7 or toY < 0 or toY > 7:
    return false
  
  let targetPiece = findPieceAt(toX, toY)
  if targetPiece != nil and targetPiece.color == piece.color:
    return false
  
  if piece.kind == King and abs(toX - fromX) == 2 and toY == fromY:
    return isValidCastling(piece, fromX, fromY, toX, toY)
  
  return true

proc evaluateCurrentPosition(): float =
  let currentMoves = getBestMoves(gameState)
  if currentMoves.len > 0:
    let rawScore = currentMoves[0].score
    if gameState.currentTurn == White:
      return rawScore
    else:
      return -rawScore
  return 0.0

proc handleInput*(squareSize: Vector2) =
  let mousePos = getMousePosition()
  let (gridX, gridY) = getAdjustedGridPosition(mousePos, squareSize)
  
  if isKeyPressed(R):
    initializeGame()
  elif isKeyPressed(F):
    gameState.flipped = not gameState.flipped

  if pendingPromotion != nil:
    if isMouseButtonPressed(MouseButton.Left):
      for button in gameState.promotionButtons:
        if checkCollisionPointRec(mousePos, button.rect):
          pendingPromotion.kind = button.kind
          pendingPromotion = nil
          gameState.promotionButtons = @[]
          return
    return

  if isMouseButtonPressed(MouseButton.Left):
    for piece in gameState.pieces:
      if piece.x == gridX and piece.y == gridY and piece.color == gameState.currentTurn:
        piece.dragging = true
        gameState.draggedPiece = piece
        break

  elif isMouseButtonReleased(MouseButton.Left):
    if gameState.draggedPiece != nil:
      let movingPiece = gameState.draggedPiece
      let oldX = movingPiece.x
      let oldY = movingPiece.y
      
      if not isValidMove(movingPiece, oldX, oldY, gridX, gridY):
        movingPiece.dragging = false
        gameState.draggedPiece = nil
        return
      
      let positionBeforeMove = evaluateCurrentPosition()
      var captured = false
      var capturedPiece: Piece = nil
      
      let isCastling = movingPiece.kind == King and abs(gridX - oldX) == 2
      
      if isCastling:
        executeCastling(movingPiece, gridX)
      else:
        let targetPiece = findPieceAt(gridX, gridY)
        if targetPiece != nil and targetPiece.color != movingPiece.color:
          let idx = findPieceIndex(targetPiece)
          if idx >= 0:
            capturedPiece = targetPiece
            gameState.pieces.delete(idx)
            captured = true

        # En passant
        if movingPiece.kind == Pawn:
          let direction = if movingPiece.color == White: -1 else: 1
          let startRow = if movingPiece.color == White: 4 else: 3
          if movingPiece.y == startRow and abs(gridX - movingPiece.x) == 1 and gridY == movingPiece.y + direction:
            let sidePawn = findPieceAt(gridX, movingPiece.y)
            if sidePawn != nil and sidePawn.kind == Pawn and sidePawn.color != movingPiece.color:
              let idx = findPieceIndex(sidePawn)
              if idx >= 0:
                capturedPiece = sidePawn
                gameState.pieces.delete(idx)
                captured = true

      movingPiece.x = gridX
      movingPiece.y = gridY
      movingPiece.dragging = false
      gameState.draggedPiece = nil

      # Promoção
      if movingPiece.kind == Pawn:
        let lastRow = if movingPiece.color == White: 0 else: 7
        if movingPiece.y == lastRow:
          pendingPromotion = movingPiece
          createPromotionButtons(movingPiece)
          return

      if movingPiece.x != oldX or movingPiece.y != oldY:
        let positionAfterMove = evaluateCurrentPosition()
        let moveAdvantage = positionAfterMove - positionBeforeMove
        
        gameState.currentTurn = if gameState.currentTurn == White: Dark else: White
        gameState.lastEvaluation = positionAfterMove
        
        # Iniciar período de "pensamento" para o próximo movimento
        startThinking()
        
        gameState.suggestedMoves = getBestMoves(gameState)

# [Resto das funções auxiliares permanecem iguais]

proc getBoardPosition*(x, y: int): Vector2 =
  let squareSize = Vector2(
    x: float(getScreenWidth()) / 8.0,
    y: float(getScreenHeight()) / 8.0
  )
  if gameState.flipped:
    result = Vector2(
      x: float(7 - x) * squareSize.x,
      y: float(7 - y) * squareSize.y
    )
  else:
    result = Vector2(
      x: float(x) * squareSize.x,
      y: float(y) * squareSize.y
    )

proc getBoardCenter*(x, y: int): Vector2 =
  let squareSize = Vector2(
    x: float(getScreenWidth()) / 8.0,
    y: float(getScreenHeight()) / 8.0
  )
  let pos = getBoardPosition(x, y)
  result = Vector2(
    x: pos.x + squareSize.x / 2,
    y: pos.y + squareSize.y / 2
  )

proc isFlipped*(): bool = gameState.flipped
proc getPieces*(): seq[Piece] = gameState.pieces
proc isPromotionPending*(): bool = pendingPromotion != nil
proc getPromotionPiece*(): Piece = pendingPromotion
proc getPromotionButtons*(): seq[PromotionButton] = gameState.promotionButtons
proc getCurrentTurn*(): PieceColor = gameState.currentTurn
proc getCurrentAdvantage*(): float = gameState.lastEvaluation
proc isCurrentlyThinking*(): bool = isThinking

# Função principal para obter movimento humanizado
proc getBestBalancedMove*(): StockfishMove =
  # Se ainda está "pensando", retornar movimento vazio
  if not isThinkingComplete():
    return StockfishMove()
  
  # Finalizar período de pensamento
  if isThinking:
    finishThinking()
  
  # Retornar movimento humanizado
  return getHumanizedMove()

proc analyzeMovementTrend*(): string =
  let advantage = gameState.lastEvaluation
  let absAdvantage = abs(advantage)
  
  if absAdvantage <= 0.5:
    return "Posição equilibrada"
  elif absAdvantage <= 1.5:
    return "Vantagem leve para " & (if advantage > 0: "brancas" else: "pretas")
  elif absAdvantage <= 3.0:
    return "Vantagem clara para " & (if advantage > 0: "brancas" else: "pretas")
  elif absAdvantage <= 5.0:
    return "Grande vantagem para " & (if advantage > 0: "brancas" else: "pretas")
  else:
    return "Vantagem decisiva para " & (if advantage > 0: "brancas" else: "pretas")

proc getStrategySuggestion*(): string =
  let advantage = gameState.lastEvaluation
  let absAdvantage = abs(advantage)
  let isMyTurn = (advantage > 0 and gameState.currentTurn == White) or 
                 (advantage < 0 and gameState.currentTurn == Dark)
  
  if isThinking:
    return "Analisando posição..."
  
  if absAdvantage <= 0.5:
    return "Posição equilibrada - buscando pequenas vantagens"
  elif isMyTurn:
    if absAdvantage <= 1.5:
      return "Expandindo vantagem gradualmente"
    else:
      return "Consolidando vantagem com segurança"
  else:
    if absAdvantage <= 1.5:
      return "Buscando contraforte"
    elif absAdvantage <= 3.0:
      return "Procurando por táticas"
    else:
      return "Buscando complicações para reverter"

# Adicionar após as outras funções de get
proc getSuggestedMoves*(): seq[StockfishMove] = gameState.suggestedMoves