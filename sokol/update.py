import re

# Run from the sokol/ directory (via compile.sh). Paths are relative to CWD.
GEN_PATH = "glsl_path_gen.nim"
GEN_GLYPH = "glsl_glyph_gen.nim"
OUT_GLSL = "../src/nvg/glsl_gen.nim"
OUT_SOKOL = "../src/nvg/sokol_gen.nim"


def read_text(p: str) -> str:
    # Normalise every line ending to "\n" -- we never need to detect or
    # preserve CRLF; the generated files are written with "\n" below.
    with open(p, "r", encoding="utf-8", newline="") as f:
        return f.read().replace("\r\n", "\n").replace("\r", "\n")


def write_text(p: str, data: str):
    # Project convention: all .nim files use CRLF ("\r\n") line endings.
    # read_text() above normalises every input to "\n", so writing with
    # newline="\r\n" translates each "\n" back to "\r\n" on disk.
    with open(p, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(data)


# --------------------------------------------------------------------------
# glsl_gen.nim: extract the *Source* const blocks from both gen files and
# write them as one exported-const module. (Original behaviour, untouched.)
# --------------------------------------------------------------------------
def update_glsl_gen():
    paths = [GEN_PATH, GEN_GLYPH]
    blocks = []
    for path in paths:
        data = read_text(path)
        idx = data.find("#    #")
        idx = data.find("#    #", idx + 1)
        endIdx = data.find("proc ", idx)
        blocks.append(data[idx - 3 : endIdx].replace(": array", "*: array"))
    write_text(OUT_GLSL, "\n".join(blocks))


# --------------------------------------------------------------------------
# sokol_gen.nim: regenerate the getPathShader / getGlyphShader procs from the
# hand-named gen procs (pathShaderDesc / glyphShaderDesc). We keep the
# user-modified proc names and labels, and reference the shader sources via
# `import ./glsl_gen` (no inlined constants). Every emitted line is derived
# mechanically from the gen proc -- nothing is invented.
# --------------------------------------------------------------------------
def extract_proc_body(path: str, proc_name: str) -> str:
    data = read_text(path)
    m = re.search(
        r"^proc " + re.escape(proc_name) + r"\*\(.*?\):\s*sg\.ShaderDesc\s*=\s*\n",
        data,
        re.M,
    )
    if not m:
        raise RuntimeError("proc %s not found in %s" % (proc_name, path))
    body = data[m.end():]
    nxt = re.search(r"\nproc ", body)
    if nxt:
        body = body[: nxt.start()]
    return body


def transform_proc(body: str, new_name: str, label: str) -> str:
    # Reproduce the hand-written sokol_gen format from the gen proc body:
    #  - keep `result.` style and the `backend` parameter
    #  - return `ShaderDesc` (sg. prefix dropped from the signature), no
    #    makeShader() wrapper at the end
    #  - re-indent: gen levels 1&2 -> 2 spaces, level 3+ -> 4+ spaces
    #    (the hand style puts `case`/`of`/`else` at one indent and the
    #     branch body one indent deeper)
    #  - `case backend:` keeps its line but loses the trailing colon
    #  - `cast[cstring](addr(X))` becomes `cast[cstring](X[0].addr)` (user fix)
    #  - a blank line follows `result.label` (user format)
    out = ["proc %s*(backend: Backend): ShaderDesc =" % new_name]
    for raw in body.split("\n"):
        if raw.strip() == "":
            continue
        gi = len(raw) - len(raw.lstrip(" "))
        level = gi // 4
        si = 2 + 2 * max(0, level - 2)  # gen 4/8/12 -> 2/2/4
        content = raw.strip()
        if content.startswith("result.label ="):
            out.append(" " * si + 'result.label = "%s"' % label)
            out.append("")  # blank line after label (user format)
            continue
        if content == "case backend:":
            out.append(" " * si + "case backend")
            continue
        content = re.sub(
            r"cast\[cstring\]\(addr\(([\w]+)\)\)",
            r"cast[cstring](\1[0].addr)",
            content,
        )
        out.append(" " * si + content)
    return "\n".join(out)


def update_sokol_gen():
    path_body = extract_proc_body(GEN_PATH, "pathShaderDesc")
    glyph_body = extract_proc_body(GEN_GLYPH, "glyphShaderDesc")
    parts = [
        "import ./glsl_gen",
        "",
        "import pkg/sokol/gfx",
        "",
        transform_proc(path_body, "getPathShaderDesc", "nvg.pathShader"),
        "",
        transform_proc(glyph_body, "getGlyphShaderDesc", "nvg.glyphShader"),
    ]
    text = "\n".join(parts)
    write_text(OUT_SOKOL, text + "\n")


def main():
    update_glsl_gen()
    update_sokol_gen()


main()
