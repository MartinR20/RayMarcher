#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include "unistd.h"
#include "fcntl.h"

// 
// This is the main file of the project which will show the animated renderd Scene.
// The other file is was just used to render a frame of the RayMarcher to a bitmap.
//

#define u0  void

#define s8  signed char
#define s16 short
#define s32 int
#define s64 long

#define u8  unsigned char
#define u16 unsigned short
#define u32 unsigned int
#define u64 unsigned long

#define f32 float
#define f64 double

#define DEBUG 0

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

@interface MetalView : MTKView
- (struct CGSize)windowWillResize:(NSWindow *)sender 
                 toSize:(struct CGSize)frameSize;
@end

@interface MetalApp : NSObject <NSApplicationDelegate, NSWindowDelegate> {
    NSWindow *Window;
    MetalView *MainView;
}
@end

@implementation MetalApp : NSObject
- (id)init {
    if (self = [super init]) {
      // Window.
      NSRect frame = NSMakeRect(0, 0, 1200, 800);
      u32 StyleMask = NSTitledWindowMask|NSWindowStyleMaskClosable|
                      NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable;
      Window = [[NSWindow alloc]
                     initWithContentRect:frame styleMask:StyleMask
                     backing:NSBackingStoreBuffered defer:0];
      [Window cascadeTopLeftFromPoint:NSMakePoint(20,20)];
      [Window setDelegate:self];
      Window.title = [[NSProcessInfo processInfo] processName];
      Window.showsResizeIndicator = 1;

      // Custom MTKView.
      MainView = [[MetalView alloc] initWithFrame:frame];
      Window.contentView = MainView;
    }
    return self;
}

- (struct CGSize)windowWillResize:(NSWindow *)sender 
                 toSize:(struct CGSize)frameSize {
    return [MainView windowWillResize:sender toSize:frameSize];
}

- (u0)applicationWillFinishLaunching:(NSNotification *)notification {
    [Window makeKeyAndOrderFront:self];
}

- (s8)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication {
    return 1;
}

- (u0)dealloc {
    [Window release];
    [super dealloc];
}

@end

// The main view.
@implementation MetalView {
    id <MTLLibrary> _library;
    id <MTLCommandQueue> _commandQueue;
    id <MTLRenderPipelineState> PipelineState;
    id <MTLDepthStencilState> _depthState;
    dispatch_semaphore_t _semaphore;
    id <MTLBuffer> _uniformBuffer;
    id <MTLBuffer> _vertexBuffer;
    u32 _Frame;
}

- (id)initWithFrame:(CGRect)inFrame {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:inFrame device:device];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup {
   // Set view settings.
   self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
   self.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
   _Frame = 0;

   // Load shaders.
   NSError *error = nil;
   _library = [self.device newLibraryWithFile: @"shaders.metallib" error:&error];
   if (!_library) {
       NSLog(@"Failed to load library. error %@", error);
       exit(0);
   }
   id <MTLFunction> vertFunc = [_library newFunctionWithName:@"vert"];
   id <MTLFunction> fragFunc = [_library newFunctionWithName:@"frag"];

   // Create depth state.
   MTLDepthStencilDescriptor *depthDesc = [MTLDepthStencilDescriptor new];
   depthDesc.depthCompareFunction = MTLCompareFunctionLess;
   depthDesc.depthWriteEnabled = YES;
   _depthState = [self.device newDepthStencilStateWithDescriptor:depthDesc];

   // Create vertex descriptor.
   MTLVertexDescriptor *VertexDescriptor = [MTLVertexDescriptor new];
   VertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormatFloat3;
   VertexDescriptor.attributes[VertexAttributePosition].offset = 0;
   VertexDescriptor.attributes[VertexAttributePosition].bufferIndex = MeshVertexBuffer;
   VertexDescriptor.layouts[MeshVertexBuffer].stride = sizeof(f32) * 3;
   VertexDescriptor.layouts[MeshVertexBuffer].stepRate = 1;
   VertexDescriptor.layouts[MeshVertexBuffer].stepFunction = MTLVertexStepFunctionPerVertex;

   // Create pipeline state.
   MTLRenderPipelineDescriptor *PipelineDescriptor = [MTLRenderPipelineDescriptor new];
   PipelineDescriptor.sampleCount = self.sampleCount;
   PipelineDescriptor.vertexFunction = vertFunc;
   PipelineDescriptor.fragmentFunction = fragFunc;
   PipelineDescriptor.vertexDescriptor = VertexDescriptor;
   PipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
   PipelineDescriptor.depthAttachmentPixelFormat = self.depthStencilPixelFormat;
   PipelineDescriptor.stencilAttachmentPixelFormat = self.depthStencilPixelFormat;
   PipelineState = [self.device newRenderPipelineStateWithDescriptor:PipelineDescriptor error:&error];
   if (!PipelineState) {
       NSLog(@"Failed to create pipeline state, error %@", error);
       exit(0);
   }

	_uniformBuffer = [self.device newBufferWithLength:sizeof(struct uniforms)
  			                                    options:MTLResourceCPUCacheModeWriteCombined];
	_semaphore = dispatch_semaphore_create(1);

	struct uniforms *Uniforms = (struct uniforms *)[_uniformBuffer contents];
	Uniforms->Width  = 1200;
	Uniforms->Height = 800;

   // Create vertices.
   f32 Verticis[2][3][3] = {
       {{-1.0,  1.0, 0.0},
        { 1.0,  1.0, 0.0},
        {-1.0, -1.0, 0.0}},
	    {{-1.0, -1.0, 0.0},
        { 1.0,  1.0, 0.0},
	  	  { 1.0, -1.0, 0.0}}
   };

	id <MTLBuffer> _sourceBuffer;

   _sourceBuffer = [self.device newBufferWithBytes:Verticis
                                            length:sizeof(Verticis)
                                           options:MTLResourceStorageModeShared];

   _vertexBuffer = [self.device newBufferWithLength:sizeof(Verticis)
                                            options:MTLResourceStorageModePrivate];

   // Create command queue
   _commandQueue = [self.device newCommandQueue];

	// Create a command buffer for GPU work.
	id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
	
	// Encode a blit pass to copy data from the source buffer to the private buffer.
	id <MTLBlitCommandEncoder> BlitCommandEncoder = [commandBuffer blitCommandEncoder];
	[BlitCommandEncoder copyFromBuffer:_sourceBuffer
	                      sourceOffset:0
	                          toBuffer:_vertexBuffer
	                 destinationOffset:0 size:sizeof(Verticis)];
	[BlitCommandEncoder endEncoding];
	
	[commandBuffer commit];
}

- (struct CGSize)windowWillResize:(NSWindow *)sender 
                 toSize:(struct CGSize)frameSize {

    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    
    struct uniforms *Uniforms = (struct uniforms *)[_uniformBuffer contents];
    Uniforms->Width  = frameSize.width;
    Uniforms->Height = frameSize.height;

    dispatch_semaphore_signal(_semaphore);
    return frameSize;
}


- (void)drawRect:(CGRect)rect {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);

    ++_Frame;
    struct uniforms *Uniforms = (struct uniforms *)[_uniformBuffer contents];
    Uniforms->Frame = _Frame;

    // Create a command buffer.
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    // Encode render command.
    id <MTLRenderCommandEncoder> RenderCommandEncoder =
         [commandBuffer renderCommandEncoderWithDescriptor:self.currentRenderPassDescriptor];
    
    MTLViewport Viewport = {0, 0, self.drawableSize.width, self.drawableSize.height, 0, 1};
    
    [RenderCommandEncoder setViewport:Viewport];
    [RenderCommandEncoder setDepthStencilState:_depthState];
    [RenderCommandEncoder setRenderPipelineState:PipelineState];
    [RenderCommandEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:MeshVertexBuffer];
    [RenderCommandEncoder setVertexBuffer:_uniformBuffer offset:0 atIndex:UniformBuffer];
    [RenderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    [RenderCommandEncoder endEncoding];
    
    // Set callback for semaphore.
    __block dispatch_semaphore_t semaphore = _semaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(semaphore);
    }];
    [commandBuffer presentDrawable:self.currentDrawable];
    [commandBuffer commit];
    
    // Draw children.
    [super drawRect:rect];
}

@end

s32 main() {
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    NSApplication * application = [NSApplication sharedApplication];
#if !DEBUG 
    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
#endif
    [application activateIgnoringOtherApps:0];

    MetalApp * appDelegate = [[[MetalApp alloc] init] autorelease];

    [application setDelegate:appDelegate];
    [application run];

    [pool drain];

    [[MetalApp alloc] init];
    [application setDelegate:appDelegate];
    [application run];

    return 0;
}

