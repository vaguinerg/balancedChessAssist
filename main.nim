import raylib
import pieces
import game
import types
import board
import strformat
import renderer

setTraceLogLevel(None)
setConfigFlags(flags(WindowResizable, Msaa4xHint, VsyncHint))
initWindow(800, 600, "Balanced Chess Assist")

const
    LightBrown = Color(r: 210, g: 180, b: 140, a: 255)
    DarkBrown = Color(r: 139, g: 69, b: 19, a: 255)
    
var chessboardTexture = loadTextureFromImage(genImageChecked(2, 2, 1, 1, LightBrown, DarkBrown))

loadPieceTextures()
initializeGame()

while not windowShouldClose():
    let squareSize = getSquareSize()
    handleInput(squareSize)
    
    drawing:
        clearBackground(RAYWHITE)
        drawBoard(chessboardTexture)
        for piece in getPieces():
            drawPiece(piece, squareSize)
        
        # Desenhar botões de promoção
        if isPromotionPending():
            drawRectangle(0'i32, 0'i32, getScreenWidth(), getScreenHeight(), Color(r: 0, g: 0, b: 0, a: 128))
            let p = getPromotionPiece()
            for button in getPromotionButtons():
                drawRectangle(int32 button.rect.x, int32 button.rect.y,
                            int32 button.rect.width, int32 button.rect.height, RAYWHITE)
                let dummyPiece = Piece(
                    kind: button.kind,
                    color: p.color,
                    x: 0, y: 0,
                    dragging: false
                )
                # Usar a posição do botão para desenhar a peça
                drawPiece(dummyPiece, Vector2(
                    x: button.rect.x,
                    y: button.rect.y
                ), Vector2(
                    x: button.rect.width,
                    y: button.rect.height
                ))
        
        # Desenhar informação de vantagem
        let advantage = getCurrentAdvantage()
        let advText = fmt"Vantagem: {advantage:.2f}"
        drawText(advText, 10'i32, 10'i32, 20'i32, 
                if advantage > 0: GREEN elif advantage < 0: RED else: GRAY)
        
        # Desenhar linha da melhor jogada balanceada
        if not isPromotionPending():
            let bestMove = getBestBalancedMove()
            # Verificar se o movimento é válido (não vazio)
            if bestMove.fromX >= 0 and bestMove.fromX <= 7 and 
               bestMove.fromY >= 0 and bestMove.fromY <= 7 and
               bestMove.toX >= 0 and bestMove.toX <= 7 and
               bestMove.toY >= 0 and bestMove.toY <= 7:
                let startPos = getBoardCenter(bestMove.fromX, bestMove.fromY)
                let endPos = getBoardCenter(bestMove.toX, bestMove.toY)
                drawLine(
                    startPos,
                    endPos,
                    3.0,
                    Color(r: 0, g: 255, b: 0, a: 128)
                )
        
        drawAllSuggestedMoves()

closeWindow()