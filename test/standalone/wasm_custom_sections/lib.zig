// FIXME: This PR implements support for both `linksection` and `@wasmCustomSection`.
//  We are still discussing which to support.
//  Once we do, we can delete one approach.
//  See `https://codeberg.org/ziglang/zig/issues/36224` for links to old Zulip chats
//  where `@wasmCustomSection` was suggested by a core maintainer.

export const utf8 linksection(".custom_section.is-utf8") = [_]u8{ 'a', 'b', 'c', 'd' };
// export const non_utf8 linksection(".custom_section.non-utf8") = [_]u8{ 255, 254, 253 };
export const duplicate_name_1 linksection(".custom_section.dupe-name") = [_]u8{ 'o', 'n', 'e' };
// export const duplicate_name_2 linksection(".custom_section.dupe-name") = [_]u8{ 't', 'w', 'o' };

comptime {
    // @wasmCustomSection("is-utf8", "abcd");
    @wasmCustomSection("non-utf8", &[_]u8{ 255, 254, 253 });
    // @wasmCustomSection("dupe-name", "one");
    @wasmCustomSection("dupe-name", "two");
}
