import raylib
import types
import strutils
import game
import board  # novo import

type TextureRef = ref object
  texture: Texture2D

var pieceTextures: array[PieceColor, array[PieceKind, TextureRef]]

proc loadPieceTextures*() =
  for color in PieceColor:
    for kind in PieceKind:
      let colorStr = if color == White: "white" else: "dark"
      let kindStr = toLowerAscii($kind)
      let path = "assets/" & colorStr & "_" & kindStr & ".png"
      var textureRef = new TextureRef
      textureRef.texture = loadTexture(path)
      pieceTextures[color][kind] = textureRef

proc drawPiece*(piece: Piece, squareSize: Vector2) =
  if piece == nil: return
  
  let textureRef = pieceTextures[piece.color][piece.kind]
  if textureRef == nil: return
  
  let finalPosition = if piece.dragging:
    getMousePosition()
  else:
    getBoardPosition(piece.x, piece.y)  # usa posição do tabuleiro para peças normais
  
  drawTexture(
    textureRef.texture,
    Rectangle(x: 0, y: 0, width: float textureRef.texture.width, height: float textureRef.texture.height),
    Rectangle(x: finalPosition.x, y: finalPosition.y, width: squareSize.x, height: squareSize.y),
    Vector2(x: 0, y: 0),
    0.0,
    WHITE
  )

# Adicionar sobrecarga para os botões de promoção
proc drawPiece*(piece: Piece, position: Vector2, size: Vector2) =
  if piece == nil: return
  
  let textureRef = pieceTextures[piece.color][piece.kind]
  if textureRef == nil: return
  
  drawTexture(
    textureRef.texture,
    Rectangle(x: 0, y: 0, width: float textureRef.texture.width, height: float textureRef.texture.height),
    Rectangle(x: position.x, y: position.y, width: size.x, height: size.y),
    Vector2(x: 0, y: 0),
    0.0,
    WHITE
  )