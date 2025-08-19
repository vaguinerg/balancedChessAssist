import raylib

proc getSquareSize*(): Vector2 =
  Vector2(
    x: float(getScreenWidth()) / 8.0,
    y: float(getScreenHeight()) / 8.0
  )

proc drawBoard*(chessboardTexture: Texture2D) =
    let srcRect = Rectangle(x: 0.0, y: 0.0, width: 8.0, height: 8.0)
    let destRect = Rectangle(
      x: 0.0, y: 0.0,
      width: float(getScreenWidth()),
      height: float(getScreenHeight())
    )
    let origin = Vector2(x: 0.0, y: 0.0)

    drawTexture(chessboardTexture, srcRect, destRect, origin, 0.0, WHITE)