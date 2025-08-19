import osproc, strutils, options, streams
import types

proc fenPosition*(gameState: GameState): string =
  var board: array[8, array[8, string]]
  
  # Inicializa tabuleiro vazio
  for y in 0..7:
    for x in 0..7:
      board[y][x] = ""
  
  # Preenche com as peças
  for piece in gameState.pieces:
    let symbol = case piece.kind
    of Pawn: "p"
    of Knight: "n"
    of Bishop: "b"
    of Rook: "r"
    of Queen: "q"
    of King: "k"
    board[piece.y][piece.x] = if piece.color == White: symbol.toUpper else: symbol

  # Converte para FEN
  var fen = ""
  for y in 0..7:
    var empty = 0
    for x in 0..7:
      if board[y][x] == "":
        empty.inc
      else:
        if empty > 0:
          fen.add($empty)
          empty = 0
        fen.add(board[y][x])
    if empty > 0:
      fen.add($empty)
    if y < 7:
      fen.add("/")

  fen.add(" ")
  fen.add(if gameState.currentTurn == White: "w" else: "b")
  fen.add(" KQkq - 0 1")
  echo "FEN gerado: ", fen
  return fen

proc analyzePosition*(fen: string, depth: int = 15): tuple[evaluation: float, moves: seq[StockfishMove]] =
  # Usar processo interativo em vez de execCmdEx
  let process = startProcess("stockfish", options = {poUsePath, poStdErrToStdOut})
  let input = process.inputStream
  let output = process.outputStream
  
  # Enviar comandos
  input.writeLine("position fen " & fen)
  input.writeLine("setoption name MultiPV value 5")
  input.writeLine("go depth " & $depth)
  input.flush()
  
  var moves: seq[StockfishMove] = @[]
  var lastEval = 0.0
  var linesProcessed = 0
  var foundBestMove = false
  
  # Ler saída linha por linha
  while not foundBestMove and linesProcessed < 1000: # limite de segurança
    let line = output.readLine()
    linesProcessed.inc
    echo "Linha: ", line
    
    if line.startsWith("bestmove"):
      foundBestMove = true
      break
    
    if line.contains("multipv") and (line.contains("score cp") or line.contains("score mate")):
      let parts = line.split(" ")
      
      # Encontrar índices importantes
      var pvIndex = -1
      var scoreIndex = -1
      var scoreType = ""
      
      for i, part in parts:
        if part == "pv":
          pvIndex = i
        elif part == "score":
          if i + 1 < parts.len:
            scoreType = parts[i + 1]
            scoreIndex = i + 1
      
      if pvIndex > 0 and scoreIndex > 0 and pvIndex + 1 < parts.len and scoreIndex + 1 < parts.len:
        let moveStr = parts[pvIndex + 1]
        echo "- Encontrou move: ", moveStr, " score type: ", scoreType
        
        if moveStr.len >= 4:
          try:
            var score: float
            if scoreType == "cp":
              score = parseFloat(parts[scoreIndex + 1]) / 100.0
            elif scoreType == "mate":
              # Para mate, usar valor muito alto/baixo dependendo do sinal
              let mateIn = parseInt(parts[scoreIndex + 1])
              score = if mateIn > 0: 999.0 else: -999.0
            else:
              continue
            
            # Converter notação algébrica para coordenadas
            if moveStr[0] >= 'a' and moveStr[0] <= 'h' and
               moveStr[1] >= '1' and moveStr[1] <= '8' and
               moveStr[2] >= 'a' and moveStr[2] <= 'h' and
               moveStr[3] >= '1' and moveStr[3] <= '8':
              
              let move = StockfishMove(
                fromX: ord(moveStr[0]) - ord('a'),
                fromY: 8 - (ord(moveStr[1]) - ord('0')),
                toX: ord(moveStr[2]) - ord('a'),
                toY: 8 - (ord(moveStr[3]) - ord('0')),
                score: score
              )
              echo "- Parsed move: fromX=", move.fromX, " fromY=", move.fromY,
                   " toX=", move.toX, " toY=", move.toY, " score=", move.score
              moves.add(move)
              if moves.len == 1:
                lastEval = score
          except ValueError as e:
            echo "- Erro ao converter: ", e.msg
  
  # Fechar processo
  input.writeLine("quit")
  input.flush()
  input.close()
  output.close()
  process.close()
  
  echo "Total de moves encontrados: ", moves.len
  return (evaluation: lastEval, moves: moves)

proc getBestMoves*(gameState: GameState): seq[StockfishMove] =
  let fen = fenPosition(gameState)
  let analysis = analyzePosition(fen)
  return analysis.moves