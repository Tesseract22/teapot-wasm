const std = @import("std");
const process = std.process;
const heap = std.heap;

const startsWith = std.mem.startsWith;
const split = std.mem.split;
const tokenizeScalar = std.mem.tokenizeScalar;
const ArrayList = std.ArrayList;
const PositionList = ArrayList([4]f32);
const ColorList = ArrayList([3]f32);
const Teapot = @import("teapot.zig");

const Draw = union(enum) {
    drawArraysTriangles: [2]u32,
};
const DrawList = ArrayList(Draw);

const DepthBufType = f64;

// x,y,z,w,r,g,b,a,s,t
const X = 0;
const Y = 1;
const Z = 2;
const W = 3;
const R = 4;
const G = 5;
const B = 6;
const A = 7;
const S = 8;
const T = 9;

const Vec = @Vector(10, f32);

fn setVec(v: *Vec, slice: []f32, start: u32) void {
    // std.debug.assert(10 > start + )
    for (slice, 0..) |f, i| {
        v[start + i] = f;
    }
}

fn rgbaU32(r: f32, g: f32, b: f32, a: f32) u32 {
    return rgbaArrayToU32(.{ r, g, b, a });
}
fn rgbaArrayToU32(arr: [4]f32) u32 {
    var res: u32 = 0;
    for (arr, 0..) |color, i| {
        const c = @as(u32, @intFromFloat(color * 255));
        res += @as(u32, @intCast(c)) << (@as(u5, @intCast(i * 8)));
    }
    return res;
}

fn rgbaVecToU32(arr: @Vector(4, f32)) u32 {
    var v: @Vector(4, u32) = @intFromFloat(@as(@Vector(4, f32),@splat(255)) * arr);
    v = @min(@as(@Vector(4, u32), @splat(255)),  v);
    v *= @Vector(4, u32) {1, 1 << 8, 1 << 16, 1 << 24};
    return @reduce(.Add, v);
}



test "rgb" {
    log("\n", .{});
    log("0x{X}\n", .{rgbaArrayToU32(.{1,0,0,1})});
    log("0x{X}\n", .{rgbaVecToU32(.{1,0,0,1})});
}

fn getTypeLegnth(comptime a: type) comptime_int {
    return switch (@typeInfo(a)) {
            .Struct => |struct_info| struct_info.fields.len,
            .Array, => |array_info| array_info.len,
            .Vector => |vector_info| vector_info.len,
            else => {
                @compileError("Interpolation must be of `struct`, `Array`, or `Vector` type.");
            },
    };
}
fn getVectorFromAny(a: anytype) @Vector(getTypeLegnth(@TypeOf(a)), f32)  {
    const N = getTypeLegnth(@TypeOf(a));
    var v: @Vector(N, f32) = undefined;
    switch (@typeInfo(@TypeOf(a))) {
        .Struct => |info| {
            inline for (info.fields, &v) |field, *vi| {
                vi.* = @field(a, field.name);
            }
        },
        .Array,  => |_| {
            inline for (a, 0..) |ai, i| {
                v[i] = ai;
            }
        },
        .Vector,  => |_| {
            v = a;
        },
        else => @compileError("only `struct`, `Array`, and `Vector` is supported"),
    }
    return v;
}

const Canvas = struct {
    pub fn DDAIterator(comptime N: comptime_int) type {
        const VecN = @Vector(N, f32);
        return struct {
            p: VecN,
            s: VecN,
            bd: f32,
            axis: u8,
            pub fn next(self: *@This()) ?VecN {
                if (self.p[self.axis] < self.bd) {
                    defer self.p += self.s;
                    return self.p;
                }
                return null;
            }
        };
        
    }

    width: u32,
    height: u32,
    data: []u32,
    depth: []DepthBufType,
    pub fn init(width: u32, height: u32, data: []u32, depth: []DepthBufType) !Canvas {
        std.debug.assert(data.len == width * height);
        std.debug.assert(depth.len == width * height);
        return .{ .height = height, .width = width, .data = data, .depth = depth };
    }

    pub fn resetDepth(self: *Canvas) void {
        @memset(self.depth, std.math.floatMin(f32));
    }

    pub fn resize(self: *Canvas, width: u32, height: u32, data: []u8) !void {
        self.data = data;
        self.height = height;
        self.width = width;
    }
    pub fn deinit(self: *Canvas) void {
        self.allocator.free(self.data);
    }
    pub fn set(self: *Canvas, pos: [3]f32, el: u32) void {
        if (pos[0] < 0 or pos[0] >= @as(f32, @floatFromInt(self.width)) or pos[1] < 0 or pos[1] >= @as(f32, @floatFromInt(self.height))) return;
        const x: u32 = @intFromFloat(pos[0]);
        const y: u32 = @intFromFloat(pos[1]);
        if (self.depth[y * self.width + x] >= pos[2]) {
            return;
        }
        self.depth[y * self.width + x] = pos[2];
        self.data[y * self.width + x] = el;
    }
    pub fn viewPortTransform(self: *Canvas, pos: *Vec) void {
        const w: f32 = @floatFromInt(self.width);
        const h: f32 = @floatFromInt(self.height);
        pos[0] = (pos[0] + 1) * w / 2;
        pos[1] = (pos[1] + 1) * h / 2;
    }
    pub fn viewPortTransform2(self: *Canvas, pos: anytype) void {
        const w: f32 = @floatFromInt(self.width);
        const h: f32 = @floatFromInt(self.height);
        var res = pos;
        res[0] = (pos[0] + 1) * w / 2;
        res[1] = (pos[1] + 1) * h / 2;
    }
    pub fn ShaderFn(comptime N: comptime_int) type {
        return fn (cv: *Canvas, v: @Vector(N, f32)) u32;
    }   
    pub fn drawTriangle(self: *Canvas, a: Vec, b: Vec, c: Vec) void {
        if (a[1] <= b[1] and b[1] <= c[1]) {
            var top_to_bot = DDA(10, a, c, 1) orelse {
                return;
            };
            var pos1: Vec = undefined;
            var pos2: Vec = undefined;
            if (DDA(10, a, b, 1)) |*top_to_mid| {
                while (true) {
                    pos1 = @constCast(top_to_mid).next() orelse break;
                    pos2 = top_to_bot.next() orelse break;
                    var x_dda = DDA(10, pos1, pos2, 0) orelse continue;
                    while (x_dda.next()) |pos| {
                        const pos_alt = pos / @as(Vec, @splat(pos[W]));
                        self.set(.{ pos[0], pos[1], pos[2] }, rgbaU32(pos_alt[4], pos_alt[5], pos_alt[6], pos_alt[7]));
                    }
                }
            }
            var mid_to_bot = DDA(10, b, c, 1) orelse return;
            while (true) {
                pos1 = mid_to_bot.next() orelse break;
                pos2 = top_to_bot.next() orelse break;
                var x_dda = DDA(10, pos1, pos2, 0) orelse continue;
                while (x_dda.next()) |pos| {
                    const pos_alt = pos / @as(Vec, @splat(pos[W]));
                    self.set(.{ pos[0], pos[1], pos[2] }, rgbaU32(pos_alt[4], pos_alt[5], pos_alt[6], pos_alt[7]));
                }
            }
        } else {
            if (a[1] >= b[1] and b[1] >= c[1]) {
                return drawTriangle(self, c, b, a);
            } else {
                return drawTriangle(self, b, c, a);
            }
        }
    }
    
    fn drawTriangleN(self: *Canvas, comptime N: comptime_int, a: @Vector(N, f32), b: @Vector(N, f32), c: @Vector(N, f32), shader: ShaderFn(N)) void {
        const VecN = @Vector(N, f32);
        if (a[1] <= b[1] and b[1] <= c[1]) {
            var top_to_bot = DDA(N, a, c, 1) orelse {
                return;
            };
            var pos1: VecN = undefined;
            var pos2: VecN = undefined;
            if (DDA(N, a, b, 1)) |*top_to_mid| {
                while (true) {
                    pos1 = @constCast(top_to_mid).next() orelse break;
                    pos2 = top_to_bot.next() orelse break;
                    var x_dda = DDA(N, pos1, pos2, 0) orelse continue;
                    while (x_dda.next()) |pos| {
                        const pos_alt = pos / @as(VecN, @splat(pos[W]));
                        self.set(.{ pos[0], pos[1], pos[2] }, shader(self, pos_alt));
                    }
                }
            }
            var mid_to_bot = DDA(N, b, c, 1) orelse return;
            while (true) {
                pos1 = mid_to_bot.next() orelse break;
                pos2 = top_to_bot.next() orelse break;
                var x_dda = DDA(N, pos1, pos2, 0) orelse continue;
                while (x_dda.next()) |pos| {
                    const pos_alt = pos / @as(VecN, @splat(pos[W]));
                    self.set(.{ pos[0], pos[1], pos[2] }, shader(self, pos_alt));
                }
            }
        } else {
            if (a[1] >= b[1] and b[1] >= c[1]) {
                return drawTriangleN(self, N, c, b, a, shader);
            } else {
                return drawTriangleN(self, N, b, c, a, shader);
            }
        }
    }
    pub fn drawTriangleRaw(self: *Canvas, a: anytype, b: anytype, c: anytype, shader: ShaderFn(getTypeLegnth(@TypeOf(a)))) void {
        const N = comptime getTypeLegnth(@TypeOf(a));
        comptime {
            if (N < 4) {
                @compileError(std.fmt.comptimePrint("Expect point length >= 4, got {}", .{N}));
            }
            if (N != getTypeLegnth(@TypeOf(b))) {
                @compileError(std.fmt.comptimePrint("length of a ({}) != length of b ({})", .{N,  getTypeLegnth(@TypeOf(b))}));
            }
            if (N != getTypeLegnth(@TypeOf(c))) @compileError("length of a != length of c");
        }


        var vecs: [3]@Vector(N, f32) = undefined;
        vecs[0] = getVectorFromAny(a);
        vecs[1] = getVectorFromAny(b);
        vecs[2] = getVectorFromAny(c);
        
        for (&vecs) |*v| {
            v[W] = v[Z];
            v[Z] = (far+near) / (far-near) * v[Z] + (-2*near*far) / (far-near);
            const w = v[W];
            // clipping
            if (v[X] > w or v[X] < -w or v[Y] > w or v[Y] < -w or v[Z] > w or v[Z] < -w) return;
            // divide everything by w, except w => 1/w instead of 1
            v.* /= @splat(w);
            v[W] = 1/w;
            cv.viewPortTransform2(v);
        }
        self.drawTriangleN(N, vecs[0], vecs[1], vecs[2], shader);
        
        
    }
    pub fn fill(self: *Canvas, el: u32) void {
        @memset(self.data, el);
    }
    // pub fn DDA(a: [2]f32, b: [2]f32, axis: u8) ?DDAIterator {
    //     if (a[axis] == b[axis]) return null;
    //     if (a[axis] > b[axis]) return DDA(b, a, axis);
    //     const delta: [2]f32 = .{ b[0] - a[0], b[1] - a[1] };
    //     const s: [2]f32 = .{ delta[0] / delta[axis], delta[1] / delta[axis] };
    //     const e = @ceil(a[axis]) - a[axis];
    //     const p: [2]f32 = .{ a[0] + e * s[0], a[1] + e * s[1] };
    //     return .{ .p = p, .s = s, .axis = axis, .bd = b[axis] };
    // }
    pub fn DDA(comptime N: comptime_int, a: @Vector(N, f32), b: @Vector(N, f32), axis: u8) ?DDAIterator(N) {
        const VecN = @Vector(N, f32);
        if (a[axis] == b[axis]) return null;
        if (a[axis] > b[axis]) return DDA(N, b, a, axis);
        const delta = b - a;
        const s = delta / @as(VecN, @splat(delta[axis]));
        const e = @ceil(a[axis]) - a[axis];
        const p = a + @as(VecN, @splat(e)) * s;
        return .{ .p = p, .s = s, .axis = axis, .bd = b[axis] };
    }
};
const ParserError = error{
    InvalidCharacter,
    Overflow,
};
fn Parser(comptime TT: type) type {
    return fn ([]const u8) ParserError!TT;
}


const vecMaker = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 0,
    r: f32 = 0,
    g: f32 = 0,
    b: f32 = 0,
    a: f32 = 0,
    s: f32 = 0,
    t: f32 = 0,
};

fn vec(v: vecMaker) Vec {
    return Vec {v.x, v.y, v.z, v.w, v.r, v.g, v.b, v.a, v.s, v.t};
}

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
    return .{
        v1[Y] * v2[Z] - v1[Z] * v2[Y], -(v1[X] * v2[Z] - v1[Z] * v2[X]),
            v1[X] * v2[Y] - v1[Y] * v2[X]
    };
}

fn faceNormal(a: anytype, b: @TypeOf(a), c: @TypeOf(a)) @TypeOf(a) {
    const Type = @TypeOf(a);
    return crossProduct(  Type {a[0]-b[0],a[1]-b[1],a[2]-b[2]}, Type {a[0]-c[0],a[1]-c[1],a[2]-c[2]});
    
}

const Vec3 = @Vector(3, f32);

const join = std.simd.join;
const extract = std.simd.extract;
fn teapotShader(self: *Canvas, v: @Vector(11, f32)) u32 {
    _ = self;
    const color = @Vector(3, f32) {v[4], v[5], v[6]};
    const normal = normalize(Vec3 {v[8], v[9], v[10]});
    const lambert: f32 = @max(@reduce(.Add,(normal * light_dir)), 0.0);
    var blinn: f32 = @max(@reduce(.Add,(normal * halfway)), 0);
    blinn = std.math.pow(f32, blinn,300);
    
    var final_color = light_color * @as(Vec3 ,@splat(lambert)) * color;
    final_color += @splat(blinn * 0.5);
    return rgbaVecToU32(std.simd.join(final_color,  extract(v, A, 1))) ;
}

fn teapotShader2(self: *Canvas, v: @Vector(10, f32)) u32 {
    _ = self;
    return rgbaU32(v[4], v[5], v[6], v[7]);
}

fn normalize(v: anytype) @TypeOf(v) {
    if (@typeInfo(@TypeOf(v)) == .Vector) {
        return v / @as(@TypeOf(v) ,@splat(vecLen(v)));
    }
    var sum: f32 = 0;
    for (v) |vi| {
        sum += (vi * vi);
    }
    sum = @sqrt(sum);
    if (sum == 0) return v;
    var res = v;
    for (res, 0..) |_, i| {
        res[i] /= sum;
    }
    return res;
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

fn vecLen(v: anytype) f32 {
    return @sqrt(@reduce(.Add, v * v));
}

const light_dir =  normalize(@Vector(3, f32) {0.2, -0.3, 1});
const halfway = normalize(light_dir + Vec3 {0, 0, 1});
const light_color = @Vector(3, f32) {1, 1, 1};

const cv_width = 512;
const cv_height = 512;
const teapot_w = 5;
const far: f32 = 0.5;
const near: f32 = -0.5;
var buf: [cv_width * cv_height]u32 = undefined;
var depth_buf: [cv_width * cv_height]DepthBufType = undefined;
var ns = [_][3]f32 {.{0} ** 3 } ** Teapot.vs.len; 
var cv = Canvas.init(cv_width, cv_height, &buf, &depth_buf) catch unreachable;

export fn HEIGHT() u32 { return cv_height; }
export fn WIDTH() u32 { return cv_width; }
export fn CANVAS() *anyopaque { return cv.data.ptr; }
export fn render(time: usize) usize {
    if (!calculated) {
        calculated = true;
        calNormals();
    }
    cv.fill(0xff301010);
    cv.resetDepth();
    const t: f32 = @as(f32, @floatFromInt(time)) / 1000;
    for (Teapot.fs) |face| {
        var vecs: [3][11]f32 = undefined;
        for (face, 0..) |p, i| {
            // calculate rotated normal
            var n3 = ns[p - 1];
            rotate(&n3[X], &n3[Z], t);
            const point3 = Teapot.vs[p - 1];
            const ci: f32 = @floatFromInt(i);
            var v = [_]f32 {point3[0], -point3[1]+2, point3[2], 1, 1-0.2*ci, 0.8, 0.2+0.2*ci, 1, n3[0], n3[1], n3[2]};
            rotate(&v[X], &v[Z], t);
            v[Z] += 5;
            vecs[i] = v;
        }
        const normal = normalize(faceNormal(vecs[0][0..3].*, vecs[1][0..3].*, vecs[2][0..3].*));
        if (normal[Z] < -0.5) continue;
        // cv.drawTriangleN(10, vecs[0], vecs[1], vecs[2], teapotShader2);
        cv.drawTriangleRaw(vecs[0], vecs[1], vecs[2], teapotShader);
    
    }    
    var ct: u32 = 0;



    return ct;
}

pub fn main() !void {
    std.debug.print("vector length: {}\n", .{vecLen(normalize(halfway))});

    std.debug.print("{}\n", .{render(0)});
}
