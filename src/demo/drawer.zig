const Canvas = @import("Canvas");
const util = Canvas.util;

const cv_width = 128;
const cv_height = 128;
var buf: [cv_width * cv_height]util.Color4 = undefined;
var cv = Canvas.init(cv_width, cv_height, &buf, null) catch unreachable;

// export fn KEY_ARROW_UP(time_passed: usize) void {
//     tilt += @as(f32,@floatFromInt(time_passed))  * 0.001;
// }
// export fn KEY_ARROW_DOWN(time_passed: usize) void {
//     tilt -= @as(f32,@floatFromInt(time_passed))  * 0.001;
// }
export fn HEIGHT() u32 { return cv_height; }
export fn WIDTH() u32 { return cv_width; }
export fn CANVAS() *anyopaque { return cv.data.ptr; }
export fn RENDER(time: usize) usize {
    _ = time;
    
    cv.fillU32(0xff301010);

    
    var ct: u32 = 0;



    return ct;
}