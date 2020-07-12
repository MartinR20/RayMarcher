#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include "unistd.h"
#include "fcntl.h"

// 
// This file was just created to render a frame to bitmap for display.
//

#define u0  void

#define s8  char
#define s16 short
#define s32 int
#define s64 long

#define u8  unsigned char
#define u16 unsigned short 
#define u32 unsigned int
#define u64 unsigned long

#define f32 float
#define f64 double

#define DEBUG 1

enum VertexAttributes {
    VertexAttributePosition = 0,
    VertexAttributeColor = 1,
};

enum BufferIndex  {
    MeshVertexBuffer = 0,
    UniformBuffer = 1,
};

struct uniforms {
	u16 Width;
	u16 Height;
   u32 Frame;
};

#pragma pack(1)

struct BMPHeader {
    // FILEHEADER
    u16 bfType;
    u32 bfSize;
    u32 bfReserved;
    u32 bfOffBits;     

    // INFOHEADER
    u32 biSize;
    s32 biWidth;
    s32 biHeight;
    u16 biPlanes;
    u16 biBitCount;
    u32 biCompression;
    u32 biSizeImage;
    s32 biXPelsPerMeter;
    s32 biYPelsPerMeter;
    u32 biClrUsed;
    u32 biClrImportant;
};

#pragma options align=reset

u0 SaveBitmap(u8 *Buffer, s32 Width, s32 Height, const char *FileName) {
    u8 *FileBuffer, *_FileBuffer;
    s32 File;
    u32 x, y, FPixel, Pixel;
    struct BMPHeader Header;
    
    Header.bfType = 0x4D42;
    Header.bfSize = sizeof(Header) + Width * Height * 3;
    Header.bfReserved = 0;
    Header.bfOffBits = sizeof(Header);

    Header.biSize = 40;
    Header.biWidth = Width;
    Header.biHeight = Height;
    Header.biPlanes = 1;
    Header.biBitCount = 24;
    Header.biCompression = 0;
    Header.biSizeImage = Width * Height * 3;
    Header.biXPelsPerMeter = 0;
    Header.biYPelsPerMeter = 0;
    Header.biClrUsed = 0;
    Header.biClrImportant = 0;

    FileBuffer = (u8 *)mmap(0, Header.bfSize, 0x3, 0x1001, -1, 0); 
    _FileBuffer = FileBuffer + sizeof(Header);

    memcpy(FileBuffer, &Header, sizeof(Header));

    for(y = 0; y < Height; ++y) {
        for(x = 0; x < Width; ++x) {
           
            FPixel = Width * Height * 3 - y * Width * 3 - x * 3;
            Pixel  = y * Width * 4 + x * 4;

            _FileBuffer[FPixel] = Buffer[Pixel];
            _FileBuffer[FPixel + 1] = Buffer[Pixel + 1];
            _FileBuffer[FPixel + 2] = Buffer[Pixel + 2];
        }
    }

    File = open(FileName, 0x201, 0644);

    write(File, FileBuffer, Header.bfSize);

    close(File);
}

s32 main () {
    s32 Width, Height;
    u32 PixelFormat, DepthStencilFormat;

    id <MTLDevice> Device;
    id <MTLCommandQueue> CommandQueue;
	 id <MTLCommandBuffer> CommandBuffer;
    id <MTLTexture> Target;
    id <MTLLibrary> Library;
    id <MTLRenderPipelineState> PipelineState;
    id <MTLDepthStencilState> DepthState;
    id <MTLBuffer> SourceBuffer, UniformBuffer, VertexBuffer;
    id <MTLFunction> VertexShader, FragmentShader;
    id <MTLBlitCommandEncoder> BlitCommandEncoder; 
    id <MTLRenderCommandEncoder> RenderCommandEncoder;

    MTLRenderPassDescriptor *RenderPassDescriptor;
    MTLDepthStencilDescriptor *DepthDescriptor;
    MTLVertexDescriptor *VertexDescriptor;         
    MTLTextureDescriptor *TextureDescriptor;         
    MTLRenderPipelineDescriptor *PipelineDescriptor; 
    MTLViewport Viewport = {0, 0, Width, Height, 0, 1};

    NSError *Error;
    struct uniforms *Uniforms;


    Width = 1920;
    Height = 1080;
    Error = 0;
    PixelFormat = MTLPixelFormatBGRA8Unorm;
    DepthStencilFormat = MTLPixelFormatDepth32Float_Stencil8;

 
    Device = MTLCreateSystemDefaultDevice();
    CommandQueue = [Device newCommandQueue];

    Library = [Device newLibraryWithFile: @"Shaders.metallib" error:&Error];
    if (!Library) {
        NSLog(@"Failed to load library. error %@", Error);
        exit(0);
    }

    VertexShader = [Library newFunctionWithName:@"vert"];
    FragmentShader = [Library newFunctionWithName:@"frag"];

    // Create depth state.
    DepthDescriptor = [MTLDepthStencilDescriptor new];
    DepthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    DepthDescriptor.depthWriteEnabled = 1;
    DepthState = [Device newDepthStencilStateWithDescriptor:DepthDescriptor];
    
    // Create vertex descriptor.
    VertexDescriptor = [MTLVertexDescriptor new];
    VertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormatFloat3;
    VertexDescriptor.attributes[VertexAttributePosition].offset = 0;
    VertexDescriptor.attributes[VertexAttributePosition].bufferIndex = MeshVertexBuffer;
    VertexDescriptor.layouts[MeshVertexBuffer].stride = sizeof(f32) * 3;
    VertexDescriptor.layouts[MeshVertexBuffer].stepRate = 1;
    VertexDescriptor.layouts[MeshVertexBuffer].stepFunction = MTLVertexStepFunctionPerVertex;
    
    // Create pipeline state.
    PipelineDescriptor = [MTLRenderPipelineDescriptor new];
    PipelineDescriptor.sampleCount = 1;
    PipelineDescriptor.vertexFunction = VertexShader;
    PipelineDescriptor.fragmentFunction = FragmentShader;
    PipelineDescriptor.vertexDescriptor = VertexDescriptor;
    PipelineDescriptor.colorAttachments[0].pixelFormat = PixelFormat;
    PipelineDescriptor.depthAttachmentPixelFormat = DepthStencilFormat;
    PipelineDescriptor.stencilAttachmentPixelFormat = DepthStencilFormat;
    PipelineState = [Device newRenderPipelineStateWithDescriptor:PipelineDescriptor 
                                                           error:&Error];

    if (!PipelineState) {
        NSLog(@"Failed to create pipeline state, error %@", Error);
        exit(0);
    }

    TextureDescriptor = [MTLTextureDescriptor new]; 
    TextureDescriptor.textureType = MTLTextureType2D;
    TextureDescriptor.width = Width;
    TextureDescriptor.height = Height;
    TextureDescriptor.pixelFormat = PixelFormat;
    TextureDescriptor.storageMode = MTLStorageModeManaged;
    TextureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead; 

    Target = [Device newTextureWithDescriptor:TextureDescriptor];
    
    RenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    RenderPassDescriptor.colorAttachments[0].texture = Target;
    RenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    RenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    RenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

 	 UniformBuffer = [Device newBufferWithLength:sizeof(struct uniforms)
                                        options:MTLResourceCPUCacheModeWriteCombined];
 
 	 Uniforms = (struct uniforms *)[UniformBuffer contents];
 	 Uniforms->Width  = 1200;
 	 Uniforms->Height = 800;
 	 Uniforms->Frame = 180;
 
    // Create vertices.
    f32 Verticis[2][3][3] = {
        {{-1.0,  1.0, 0.0},
         { 1.0,  1.0, 0.0},
         {-1.0, -1.0, 0.0}},
 	    {{-1.0, -1.0, 0.0},
         { 1.0,  1.0, 0.0},
 	  	  { 1.0, -1.0, 0.0}}
    };
 
    SourceBuffer = [Device newBufferWithBytes:Verticis
                                       length:sizeof(Verticis)
                                      options:MTLResourceStorageModeShared];

    VertexBuffer = [Device newBufferWithLength:sizeof(Verticis)
                                       options:MTLResourceStorageModePrivate];

    // Create command queue
    CommandQueue = [Device newCommandQueue];


	 // Create a command buffer for GPU work.
	 CommandBuffer = [CommandQueue commandBuffer];
	 
	 // Encode a blit pass to copy data from the source buffer to the private buffer.
	 BlitCommandEncoder = [CommandBuffer blitCommandEncoder];
	 [BlitCommandEncoder copyFromBuffer:SourceBuffer
	                       sourceOffset:0
	                           toBuffer:VertexBuffer
	                  destinationOffset:0 size:sizeof(Verticis)];
	 [BlitCommandEncoder endEncoding];
	 
	 [CommandBuffer commit];


	 CommandBuffer = [CommandQueue commandBuffer];

    // Encode render command.
	 RenderCommandEncoder = 
        [CommandBuffer renderCommandEncoderWithDescriptor:RenderPassDescriptor];

#if 0
    [RenderCommandEncoder setViewport:Viewport];
#endif
    [RenderCommandEncoder setDepthStencilState:DepthState];
    [RenderCommandEncoder setRenderPipelineState:PipelineState];
    [RenderCommandEncoder setVertexBuffer:VertexBuffer offset:0 atIndex:0];
    [RenderCommandEncoder setVertexBuffer:UniformBuffer offset:0 atIndex:1];
    [RenderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    [RenderCommandEncoder endEncoding];

    [CommandBuffer commit];

    
    CommandBuffer = [CommandQueue commandBuffer];      

    BlitCommandEncoder = [CommandBuffer blitCommandEncoder];
    [BlitCommandEncoder synchronizeTexture:Target slice:0 level:0];
    [BlitCommandEncoder endEncoding];

    [CommandBuffer commit];


    [CommandBuffer waitUntilCompleted];


    [CommandQueue release];
    [Device release];

    u8 *TextureData;

    TextureData = malloc(Width * Height * 4);

    [Target getBytes:TextureData bytesPerRow:Width * 4 bytesPerImage:Width * Height * 4
            fromRegion:MTLRegionMake2D(0, 0, Width, Height) mipmapLevel:0 slice:0];

    SaveBitmap(TextureData, Width, Height, "./Render.bmp");

    return 0;
}

