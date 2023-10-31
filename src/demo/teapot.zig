const std = @import("std");
const process = std.process;
const heap = std.heap;

const startsWith = std.mem.startsWith;
const split = std.mem.split;
const tokenizeScalar = std.mem.tokenizeScalar;
const ArrayList = std.ArrayList;
const PositionList = ArrayList([4]f32);
const ColorList = ArrayList([3]f32);
const Teapot = @import("model/teapot.zig");


const util = Canvas.util;











const Canvas = @import("Canvas");




fn log(comptime fmt: []const u8, args: anytype) void {
    if (@import("builtin").target.os.tag != .freestanding)
    std.debug.print(fmt, args);
}
const sin = std.math.sin;
const cos = std.math.cos;

fn rotate(x: *f32, y: *f32, angle: f32) void {
    const x_ = @cos(angle) * x.* - @sin(angle) * y.*;
    y.* = @sin(angle) * x.* + @cos(angle) * y.*;
    x.* = x_;
}

fn crossProduct(v1: anytype, v2: @TypeOf(v1)) @TypeOf(v1) {
    std.debug.assert(util.getTypeLegnth(@TypeOf(v1)) == 3);
    return .{
        v1[1] * v2[2] - v1[2] * v2[1], -(v1[0] * v2[2] - v1[2] * v2[0]),
            v1[0] * v2[1] - v1[1] * v2[0]
    };
}

fn faceNormal(a: anytype, b: @TypeOf(a), c: @TypeOf(a)) @TypeOf(a) {
    const Type = @TypeOf(a);
    return crossProduct(  Type {a[0]-b[0],a[1]-b[1],a[2]-b[2]}, Type {a[0]-c[0],a[1]-c[1],a[2]-c[2]});
    
}

const Vec3 = @Vector(3, f32);
const normalize = util.normalize;
const join = std.simd.join;
const extract = std.simd.extract;
fn teapotShader(self: *Canvas, v: @Vector(11, f32)) u32 {
    _ = self;
    const color = @Vector(3, f32) {v[4], v[5], v[6]};
    const normal = normalize(Vec3 {v[8], v[9], v[10]});
    const lambert: f32 = @max(@reduce(.Add,(normal * light_dir)), 0.0);
    var blinn: f32 = @max(@reduce(.Add,(normal * halfway)), 0);
    blinn = std.math.pow(f32, blinn,300);
    
    var final_color = light_color * @as(Vec3 ,@splat(lambert)) * color; // diffuse
    final_color += @splat(blinn * 0.5); // shiny
    final_color += color * ambient_light;
    return util.rgbaVecToU32(std.simd.join(final_color,  extract(v, 7, 1))) ;
}



var calculated = false;
fn calNormals() void {
    for (Teapot.fs) |face| {
        var vecs: [3][3]f32 = undefined;
        for (face, 0..) |p, i| {
            vecs[i] = Teapot.vs[p - 1];
        }
        const normal = faceNormal(vecs[0], vecs[1], vecs[2]);
        if (std.math.isNan(normal[0])) {
            log("n[{any}] = NaN before normalize\n", .{vecs});
        }
        for (face) |p| {
            for (normal, &ns[p - 1]) |new, *old|{
                old.* -= new;
            }
        }

    }
    for (&ns, 0..) |*n, i| {
            _ = i;
            // if (std.math.isNan(n[0])) {
            //     log("n[{}] = NaN before normalize\n", .{i});
            // }
            n.* = normalize(n.*);

    }
}



const light_dir =  normalize(@Vector(3, f32) {0, 0, 1});
const halfway = normalize(light_dir + Vec3 {0, 0, 1});
const light_color = @Vector(3, f32) {1, 1, 1};
const ambient_light = Vec3 {0.1,0.1,0.1};

const cv_width = 512;
const cv_height = 512;
const teapot_w = 5;
const far: f32 = 0.5;
const near: f32 = -0.5;
var buf: [cv_width * cv_height]util.Color4 = undefined;
var depth_buf: [cv_width * cv_height]f32 = undefined;
var ns = [_][3]f32 {.{0} ** 3 } ** Teapot.vs.len; 
var cv = Canvas.init(cv_width, cv_height, &buf, &depth_buf) catch unreachable;
var tilt: f32 = 0;

export fn KEY_ARROW_UP(time_passed: usize) void {
    tilt += @as(f32,@floatFromInt(time_passed))  * 0.001;
}
export fn KEY_ARROW_DOWN(time_passed: usize) void {
    tilt -= @as(f32,@floatFromInt(time_passed))  * 0.001;
}
export fn HEIGHT() u32 { return cv_height; }
export fn WIDTH() u32 { return cv_width; }
export fn CANVAS() *anyopaque { return cv.data.ptr; }
export fn RENDER(time: usize) usize {
    if (!calculated) {
        calculated = true;
        calNormals();
    }
    cv.fillU32(0xff301010);

    cv.resetDepth();
    const t: f32 = @as(f32, @floatFromInt(time)) / 1000;
    face_it: for (Teapot.fs) |face| {
        var vecs: [3]@Vector(11, f32) = undefined;
        for (face, 0..) |p, i| {
            // calculate rotated normal
            var n3 = ns[p - 1];
            
            rotate(&n3[0], &n3[2], t);
            // rotate(&n3[1], &n3[2], tilt);
            const point3 = Teapot.vs[p - 1];
            const ci: f32 = @floatFromInt(i);
            var v = @Vector(11, f32) {point3[0], -point3[1]+2, point3[2], 1, 1-0.2*ci, 0.8, 0.2+0.2*ci, 1, n3[0], n3[1], n3[2]};
            rotate(&v[0], &v[2], t);
            rotate(&v[1], &v[2], tilt);
            v[2] += 5;
            v = util.perspectiveTransform(far, near, v) orelse continue :face_it;
            vecs[i] = v;
        }
        const normal = normalize(faceNormal(extract(vecs[0], 0, 3), extract(vecs[1], 0, 3), extract(vecs[2], 0, 3)));
        if (normal[2] < -0.5) continue;
        cv.drawTriangleAny(vecs[0], vecs[1], vecs[2], teapotShader);
    
    }
    
    var ct: u32 = 0;



    return ct;
}

const Cursor = Canvas.util.Cursor;
const Clear = Canvas.util.Clear;
pub fn main() !void {

    const gradient = " .'`^\",:;Il!i><~+_-?][}{1)(|/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$";
    const h_scale = 15;
    const w_scale = 15;
    var stdout_file = std.io.getStdOut();
    var stdout_writer = stdout_file.writer();
    var stdout = std.io.bufferedWriter(stdout_writer);
    const hs = cv_height / h_scale;
    const ws = cv_width  / w_scale;
    var buffer = [_] util.Color4 { util.Color4.fromU32(0).* } ** (cv_height * cv_width);
    _ = try stdout_writer.write("\n");
    try Clear.clearScreen(stdout_writer);
    //_ = try stdout.write("\n");
    const stdin = std.io.getStdIn().reader();
    _ = stdin;
    const start = std.time.milliTimestamp();
    while (true) {
        const t = std.time.milliTimestamp() - start;
        // std.debug.print("t: {}\n", .{t});
        _ = RENDER(@intCast(t));
        try Cursor.saveCursor(stdout.writer());
        for (0..hs) |y| {
            const ys = y * h_scale;
            for (0..ws) |x| {
                const xs = x * w_scale;
                const new_pixel = cv.data[ys * cv_width + xs];
                const old_pixel = &buffer[ys * cv_width + xs];
                if (new_pixel.toU32().* == old_pixel.toU32().*) {
                    try Cursor.cursorForward(stdout.writer(), 1);
                } else {
                    const grey: u8 = @intFromFloat(util.color4ToGreyScale(new_pixel) * gradient.len) ;
                    old_pixel.* = new_pixel;
                    const c = gradient[gradient.len -  grey];
                    try stdout.writer().writeByte(c);
                }

            }
            // try stdout.writer().writeByte('\n');
            try Cursor.cursorNextLine(stdout.writer(), 0);
        }
        try Cursor.restoreCursor(stdout.writer());
        try stdout.flush();
        // std.time.sleep(1000000);

    }
}
