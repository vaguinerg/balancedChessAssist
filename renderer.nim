import raylib
import types
import game
import math

proc drawMoveArrow*(move: StockfishMove, color: Color) =
  let fromPos = getBoardCenter(move.fromX, move.fromY)
  let toPos = getBoardCenter(move.toX, move.toY)
  
  # Desenhar linha da seta
  drawLine(fromPos, toPos, 3.0, color)
  
  # Calcular direção para a ponta da seta
  let dx = toPos.x - fromPos.x
  let dy = toPos.y - fromPos.y
  let length = sqrt(dx * dx + dy * dy)
  let unitX = dx / length
  let unitY = dy / length
  
  # Configurar tamanho da ponta da seta
  let arrowSize = 15.0
  let arrowAngle = 30.0 * PI / 180.0
  
  # Calcular pontos para a ponta da seta
  let tipX = toPos.x - unitX * arrowSize
  let tipY = toPos.y - unitY * arrowSize
  
  let leftX = tipX + arrowSize * (cos(arrowAngle) * unitX - sin(arrowAngle) * unitY)
  let leftY = tipY + arrowSize * (sin(arrowAngle) * unitX + cos(arrowAngle) * unitY)
  
  let rightX = tipX + arrowSize * (cos(-arrowAngle) * unitX - sin(-arrowAngle) * unitY)
  let rightY = tipY + arrowSize * (sin(-arrowAngle) * unitX + cos(-arrowAngle) * unitY)
  
  # Desenhar ponta da seta
  drawTriangle(
    Vector2(x: toPos.x, y: toPos.y),
    Vector2(x: leftX, y: leftY),
    Vector2(x: rightX, y: rightY),
    color
  )

proc drawAllSuggestedMoves*() =
  let moves = getSuggestedMoves()
  for i, move in moves:
    if i >= 5: break # Limitar a 5 melhores movimentos
    
    # Criar cores diferentes para diferentes movimentos
    let alpha = 1.0 - (float(i) / 5.0)
    let moveColor = Color(
      r: 0, 
      g: 180,
      b: 0,
      a: uint8(255.0 * max(0.3, alpha))
    )
    drawMoveArrow(move, moveColor)
