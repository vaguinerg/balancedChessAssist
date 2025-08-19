import raylib
import types
import stockfish

var gameState = GameState(pieces: @[], flipped: false)
var pendingPromotion: Piece = nil

proc initializeGame*() =
  gameState.pieces = @[]
  gameState.flipped = false
  gameState.currentTurn = White
  gameState.lastEvaluation = 0.0
  gameState.suggestedMoves = @[]
  gameState.promotionButtons = @[]
  
  # Setup initial pieces
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

proc getAdjustedGridPosition(mousePos: Vector2, squareSize: Vector2): tuple[x, y: int] =
  let rawX = int(mousePos.x / squareSize.x)
  let rawY = int(mousePos.y / squareSize.y)
  
  if gameState.flipped:
    result = (x: 7 - rawX, y: 7 - rawY)
  else:
    result = (x: rawX, y: rawY)

proc findPieceAt(x, y: int): Piece =
  for piece in gameState.pieces:
    if piece.x == x and piece.y == y:
      return piece
  return nil

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
  # Verificar se é roque (rei move 2 casas horizontalmente)
  if abs(toX - fromX) != 2 or toY != fromY:
    return false
  
  # Determinar se é roque do lado do rei (kingside) ou da rainha (queenside)
  let isKingside = toX > fromX
  let rookX = if isKingside: 7 else: 0
  let rookNewX = if isKingside: toX - 1 else: toX + 1
  
  # Verificar se a torre está na posição correta
  let rook = findPieceAt(rookX, fromY)
  if rook == nil or rook.kind != Rook or rook.color != king.color:
    echo "Roque inválido: torre não encontrada em (", rookX, ",", fromY, ")"
    return false
  
  # Verificar se o caminho está livre
  let startX = min(fromX, rookX) + 1
  let endX = max(fromX, rookX) - 1
  
  for x in startX..endX:
    if findPieceAt(x, fromY) != nil:
      echo "Roque inválido: caminho bloqueado em (", x, ",", fromY, ")"
      return false
  
  # TODO: Verificar se rei ou torre já se moveram (precisaria de histórico)
  # TODO: Verificar se rei está em xeque ou passa por casa atacada
  
  echo "Roque válido detectado: ", if isKingside: "lado do rei" else: "lado da rainha"
  return true

proc executeCastling(king: Piece, toX: int) =
  # Determinar posições da torre
  let isKingside = toX > king.x
  let rookX = if isKingside: 7 else: 0
  let rookNewX = if isKingside: toX - 1 else: toX + 1
  
  # Encontrar a torre
  let rook = findPieceAt(rookX, king.y)
  if rook != nil:
    echo "Executando roque: Torre de (", rookX, ",", king.y, ") para (", rookNewX, ",", king.y, ")"
    rook.x = rookNewX
  else:
    echo "ERRO: Torre não encontrada durante execução do roque!"

proc isValidMove(king: Piece, fromX, fromY, toX, toY: int): bool =
  # Verificação básica de limites
  if toX < 0 or toX > 7 or toY < 0 or toY > 7:
    return false
  
  # Não pode mover para onde já tem peça da mesma cor
  let targetPiece = findPieceAt(toX, toY)
  if targetPiece != nil and targetPiece.color == king.color:
    return false
  
  # Verificação especial para ROQUE
  if king.kind == King and abs(toX - fromX) == 2 and toY == fromY:
    return isValidCastling(king, fromX, fromY, toX, toY)
  
  # Aqui você pode adicionar validação específica por tipo de peça
  # Por enquanto, aceita qualquer movimento válido em termos de tabuleiro
  return true

proc evaluateCurrentPosition(): float =
  # Obter avaliação da posição atual
  let currentMoves = getBestMoves(gameState)
  if currentMoves.len > 0:
    # IMPORTANTE: O score do Stockfish é sempre do ponto de vista do jogador atual
    # Precisamos normalizar para o ponto de vista das BRANCAS sempre
    let rawScore = currentMoves[0].score
    
    if gameState.currentTurn == White:
      return rawScore  # Se é turno das brancas, score positivo = vantagem branca
    else:
      return -rawScore  # Se é turno das pretas, invertemos: score positivo preto = vantagem preta (negativo para branco)
  
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
      
      # Verificar se o movimento é válido
      if not isValidMove(movingPiece, oldX, oldY, gridX, gridY):
        movingPiece.dragging = false
        gameState.draggedPiece = nil
        return
      
      # Avaliar posição antes do movimento
      let positionBeforeMove = evaluateCurrentPosition()
      
      var captured = false
      var capturedPiece: Piece = nil
      
      # Verificar se é ROQUE antes das outras lógicas
      let isCastling = movingPiece.kind == King and abs(gridX - oldX) == 2
      
      if isCastling:
        echo "Executando movimento de roque"
        executeCastling(movingPiece, gridX)
      else:
        # Captura normal
        let targetPiece = findPieceAt(gridX, gridY)
        if targetPiece != nil and targetPiece.color != movingPiece.color:
          let idx = findPieceIndex(targetPiece)
          if idx >= 0:
            capturedPiece = targetPiece
            gameState.pieces.delete(idx)
            captured = true

        # Captura especial "en passant"
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

      # Fazer o movimento
      movingPiece.x = gridX
      movingPiece.y = gridY
      movingPiece.dragging = false
      gameState.draggedPiece = nil

      # Promoção de peão
      if movingPiece.kind == Pawn:
        let lastRow = if movingPiece.color == White: 0 else: 7
        if movingPiece.y == lastRow:
          pendingPromotion = movingPiece
          createPromotionButtons(movingPiece)
          return # Não continua o processamento até escolher a promoção

      # Verificar se realmente houve movimento
      if movingPiece.x != oldX or movingPiece.y != oldY:
        echo "Movimento realizado: (", oldX, ",", oldY, ") -> (", gridX, ",", gridY, ")"
        
        # Avaliar posição depois do movimento (mantendo o mesmo turno temporariamente)
        let positionAfterMove = evaluateCurrentPosition()
        let moveAdvantage = positionAfterMove - positionBeforeMove
        
        echo "Vantagem antes: ", positionBeforeMove
        echo "Vantagem depois: ", positionAfterMove  
        echo "Diferença do movimento: ", moveAdvantage
        
        # Agora trocar o turno para obter os movimentos do oponente
        gameState.currentTurn = if gameState.currentTurn == White: Dark else: White
        gameState.lastEvaluation = positionAfterMove
        
        # Obter os melhores movimentos do oponente
        gameState.suggestedMoves = getBestMoves(gameState)
        
        echo "Turno atual: ", gameState.currentTurn
        echo "Avaliação atual: ", gameState.lastEvaluation
        echo "Moves sugeridos para o oponente: ", gameState.suggestedMoves.len
        
        for i, move in gameState.suggestedMoves:
          echo "Move ", i+1, ": (", move.fromX, ",", move.fromY, ") -> (", move.toX, ",", move.toY, ") score: ", move.score

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

proc getBestBalancedMove*(): StockfishMove =
  if gameState.suggestedMoves.len == 0:
    return StockfishMove() # Retorna movimento vazio
    
  echo "=== BUSCANDO MOVIMENTO EQUILIBRADO ==="
  echo "Vantagem atual das brancas: ", gameState.lastEvaluation
  echo "Turno atual: ", gameState.currentTurn
  
  # Separar movimentos vantajosos dos desvantajosos
  # IMPORTANTE: Para o jogador atual, score positivo = bom para ele
  var advantageousMoves: seq[StockfishMove] = @[]
  var disadvantageousMoves: seq[StockfishMove] = @[]
  
  for move in gameState.suggestedMoves:
    if move.score >= 0.0: # Movimento bom para o jogador atual
      advantageousMoves.add(move)
      let scoreForWhite = if gameState.currentTurn == White: move.score else: -move.score
      echo "Movimento VANTAJOSO para ", gameState.currentTurn, ": score=", move.score, " (para brancas: ", scoreForWhite, ")"
    else: # Movimento ruim para o jogador atual
      disadvantageousMoves.add(move)
      let scoreForWhite = if gameState.currentTurn == White: move.score else: -move.score
      echo "Movimento DESVANTAJOSO para ", gameState.currentTurn, ": score=", move.score, " (para brancas: ", scoreForWhite, ")"
  
  echo "Total - Vantajosos: ", advantageousMoves.len, " | Desvantajosos: ", disadvantageousMoves.len
  
  var bestMove: StockfishMove
  var bestBalance: float = 999999.0 # Valor muito alto para começar
  var foundMove = false
  
  # PRIORIDADE 1: Tentar encontrar movimento vantajoso que equilibre
  if advantageousMoves.len > 0:
    echo "=== ANALISANDO MOVIMENTOS VANTAJOSOS ==="
    for i, move in advantageousMoves:
      # Simular como ficaria a vantagem das brancas após este movimento
      let scoreForWhite = if gameState.currentTurn == White: move.score else: -move.score
      let newAdvantageForWhite = gameState.lastEvaluation + scoreForWhite
      let balance = abs(newAdvantageForWhite) # Quão próximo de 0 (equilibrado)
      
      echo "Move ", i+1, " vantajoso: (", move.fromX, ",", move.fromY, ")->(", move.toX, ",", move.toY, ")"
      echo "  Score para ", gameState.currentTurn, ": +", move.score
      echo "  Score para brancas: ", scoreForWhite
      echo "  Nova vantagem das brancas: ", newAdvantageForWhite, " | Equilíbrio: ", balance
      
      if balance < bestBalance:
        bestBalance = balance
        bestMove = move
        foundMove = true
        echo "  >>> NOVO MELHOR MOVIMENTO VANTAJOSO! <<<"
  
  # PRIORIDADE 2: Se não há movimentos vantajosos, pegar o menos ruim
  if not foundMove and disadvantageousMoves.len > 0:
    echo "=== NÃO HÁ MOVIMENTOS VANTAJOSOS, ANALISANDO OS RUINS ==="
    for i, move in disadvantageousMoves:
      let scoreForWhite = if gameState.currentTurn == White: move.score else: -move.score
      let newAdvantageForWhite = gameState.lastEvaluation + scoreForWhite
      let balance = abs(newAdvantageForWhite)
      
      echo "Move ", i+1, " desvantajoso: (", move.fromX, ",", move.fromY, ")->(", move.toX, ",", move.toY, ")"
      echo "  Score para ", gameState.currentTurn, ": ", move.score
      echo "  Score para brancas: ", scoreForWhite  
      echo "  Nova vantagem das brancas: ", newAdvantageForWhite, " | Equilíbrio: ", balance
      
      if balance < bestBalance:
        bestBalance = balance
        bestMove = move
        foundMove = true
        echo "  >>> MELHOR MOVIMENTO RUIM <<<"
  
  # FALLBACK: Se nada foi encontrado, usar o primeiro movimento
  if not foundMove:
    bestMove = gameState.suggestedMoves[0]
    echo "=== USANDO MOVIMENTO FALLBACK ==="
  
  let finalScoreForWhite = if gameState.currentTurn == White: bestMove.score else: -bestMove.score
  echo "MOVIMENTO FINAL ESCOLHIDO:"
  echo "  De: (", bestMove.fromX, ",", bestMove.fromY, ") Para: (", bestMove.toX, ",", bestMove.toY, ")"
  echo "  Score para ", gameState.currentTurn, ": ", bestMove.score
  echo "  Score para brancas: ", finalScoreForWhite
  echo "  Tipo: ", if bestMove.score >= 0.0: "VANTAJOSO" else: "DESVANTAJOSO"
  
  result = bestMove

proc getCurrentTurn*(): PieceColor = gameState.currentTurn
proc getCurrentAdvantage*(): float = gameState.lastEvaluation