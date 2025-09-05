def read_text(p: str) -> str:
  with open(p, "r") as f:
    return f.read()

def write_text(p: str, data: str):
  with open(p, "w") as f:
    f.write(data)

def main():
  data = read_text("glsl_gen.nim")
  idx = data.find("#    #")
  idx = data.find("#    #", idx + 1)

  endIdx = data.find("proc ", idx)

  data = data[idx - 2:endIdx].replace(": array", "*: array")

  write_text("../src/nvg/glsl.nim", data)
  print(data[endIdx:])

main()
