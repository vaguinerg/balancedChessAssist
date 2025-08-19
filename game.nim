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
    gameState.pieces.add(Piece(kind: kind, color: Dark, x: x, y: 0, hasMoved: false))
    gameState.pieces.add(Piece(kind: kind, color: White, x: x, y: 7, hasMoved: false))
    
  for x in 0..7:
    gameState.pieces.add(Piece(kind: Pawn, color: Dark, x: x, y: 1, hasMoved: false))
    gameState.pieces.add(Piece(kind: Pawn, color: White, x: x, y: 6, hasMoved: false))

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

proc isValidMove(piece: Piece, fromX, fromY, toX, toY: int): bool =
  # Verificação básica de limites
  if toX < 0 or toX > 7 or toY < 0 or toY > 7:
    return false
  
  # Não pode mover para onde já tem peça da mesma cor
  let targetPiece = findPieceAt(toX, toY)
  if targetPiece != nil and targetPiece.color == piece.color:
    return false
  
  # Aqui você pode adicionar validação específica por tipo de peça
  # Por enquanto, aceita qualquer movimento válido em termos de tabuleiro
  return true

proc evaluateCurrentPosition(): float =
  # Obter avaliação da posição atual
  let currentMoves = getBestMoves(gameState)
  if currentMoves.len > 0:
    return currentMoves[0].score
  return 0.0

proc isPathClear(fromX, toX, y: int): bool =
  let start = min(fromX, toX) + 1
  let finish = max(fromX, toX)
  
  for x in start..<finish:
    if findPieceAt(x, y) != nil:
      return false
  return true

proc handleCastling(king: Piece, fromX, toX: int): bool =
  if king.kind != King or king.hasMoved:
    return false
    
  # Roque é um movimento de 2 casas
  if abs(toX - fromX) != 2:
    return false
    
  let y = king.y
  let rookX = if toX > fromX: 7 else: 0  # Torre da direita ou esquerda
  let rook = findPieceAt(rookX, y)
  
  if rook == nil or rook.kind != Rook or rook.hasMoved:
    return false
    
  if not isPathClear(fromX, rookX, y):
    return false
    
  # Mover a torre
  let newRookX = if toX > fromX: toX - 1 else: toX + 1
  rook.x = newRookX
  rook.hasMoved = true
  return true

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
      
      # Tentar fazer roque se for o rei
      if movingPiece.kind == King and not movingPiece.hasMoved:
        if handleCastling(movingPiece, oldX, gridX):
          movingPiece.x = gridX
          movingPiece.y = gridY
          movingPiece.hasMoved = true
          movingPiece.dragging = false
          gameState.draggedPiece = nil
          
          # Trocar turno e analisar posição
          gameState.currentTurn = if gameState.currentTurn == White: Dark else: White
          gameState.suggestedMoves = getBestMoves(gameState)
          return

      # Verificar se o movimento é válido
      if not isValidMove(movingPiece, oldX, oldY, gridX, gridY):
        movingPiece.dragging = false
        gameState.draggedPiece = nil
        return
      
      # Avaliar posição antes do movimento
      let positionBeforeMove = evaluateCurrentPosition()
      
      var captured = false
      var capturedPiece: Piece = nil
      
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
    
  var bestMove = gameState.suggestedMoves[0]
  var bestBalance = abs(gameState.lastEvaluation + bestMove.score) # Soma porque o score é do ponto de vista do jogador atual
  
  echo "Procurando movimento mais equilibrado:"
  echo "Vantagem atual: ", gameState.lastEvaluation
  
  for i, move in gameState.suggestedMoves:
    # A vantagem após este movimento seria: vantagem atual + score do movimento
    let newAdvantage = gameState.lastEvaluation + move.score
    let balance = abs(newAdvantage) # Quão próximo de 0 (equilibrado)
    
    echo "Move ", i+1, ": score=", move.score, " newAdvantage=", newAdvantage, " balance=", balance
    
    # Evitar movimentos claramente ruins (que dão muita vantagem ao oponente)
    if move.score > -2.0: # Não perder mais que 2 pontos
      if balance < bestBalance:
        bestBalance = balance
        bestMove = move
        echo "Novo melhor movimento encontrado!"
  
  echo "Movimento escolhido: (", bestMove.fromX, ",", bestMove.fromY, ") -> (", bestMove.toX, ",", bestMove.toY, ")"
  result = bestMove

proc getCurrentTurn*(): PieceColor = gameState.currentTurn
proc getCurrentAdvantage*(): float = gameState.lastEvaluation