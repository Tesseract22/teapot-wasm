pub fn getTypeLegnth(comptime a: type) comptime_int {
    return switch (@typeInfo(a)) {
            .Struct => |struct_info| struct_info.fields.len,
            .Array, => |array_info| array_info.len,
            .Vector => |vector_info| vector_info.len,
            else => {
                @compileError("Interpolation must be of `struct`, `Array`, or `Vector` type.");
            },
    };
}

pub fn getVectorFromAny(a: anytype) @Vector(getTypeLegnth(@TypeOf(a)), f32)  {
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

pub fn perspectiveTransform(far: f32, near: f32, a: anytype) ?@TypeOf(a) {
    var v = a;
    v[3] = v[2];
    v[2] = (far+near) / (far-near) * v[2] + (-2*near*far) / (far-near);
    const w = v[3];
    // clipping
    if (v[0] > w or v[0] < -w or v[1] > w or v[1] < -w or v[2] > w or v[2] < -w) return null;
    // divide everything by w, except w => 1/w instead of 1
    v /= @splat(w);
    v[3] = 1/w;
    return v;
}

pub fn vecDescartesLen(v: anytype) f32 {
    return @sqrt(@reduce(.Add, v * v));
}

pub fn normalize(v: anytype) @TypeOf(v) {
    if (@typeInfo(@TypeOf(v)) == .Vector) {
        return v / @as(@TypeOf(v) ,@splat(vecDescartesLen(v)));
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
