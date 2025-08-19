import raylib

type
  PieceKind* = enum
    Bishop, King, Knight, Pawn, Queen, Rook

  PieceColor* = enum
    White, Dark

  Piece* = ref object
    kind*: PieceKind
    color*: PieceColor
    x*, y*: int
    dragging*: bool

  PromotionButton* = object
    rect*: Rectangle
    kind*: PieceKind

  StockfishMove* = object
    fromX*, fromY*: int
    toX*, toY*: int
    score*: float

  GameState* = ref object
    pieces*: seq[Piece]
    draggedPiece*: Piece
    mousePos*: Vector2
    flipped*: bool
    promotionButtons*: seq[PromotionButton]  # novo campo
    currentTurn*: PieceColor
    lastEvaluation*: float
    suggestedMoves*: seq[StockfishMove]
