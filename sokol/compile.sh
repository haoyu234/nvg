./sokol-shdc --input path.glsl --output ./glsl_path_gen.nim --slang glsl430:glsl310es:hlsl5 --no-log-cmdline --ifdef -f sokol_nim
./sokol-shdc --input glyph.glsl --output ./glsl_glyph_gen.nim --slang glsl430:glsl310es:hlsl5 --no-log-cmdline --ifdef -f sokol_nim

python ./update.py
