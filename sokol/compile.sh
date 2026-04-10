./sokol-shdc --input sokol.glsl --output ./glsl_gen.nim --slang glsl410:glsl300es:hlsl5 --no-log-cmdline --ifdef -f sokol_nim

python ./update.py
