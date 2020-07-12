set -e
clang -framework Cocoa -framework Metal -framework MetalKit -ferror-limit=4 \
		-Werror -Wno-deprecated-declarations \
		$1 
xcrun -sdk macosx metal -std=osx-metal1.1 -O2 -ferror-limit=1 \
        -c Shaders.metal -o Shaders.air 
xcrun -sdk macosx metal-ar r Shaders.metal-ar Shaders.air
xcrun -sdk macosx metallib Shaders.metal-ar -o Shaders.metallib 
./a.out
rm -f *.metallib *.metal-ar *.air
