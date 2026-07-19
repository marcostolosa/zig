export const utf8 linksection(".custom_section.is-utf8") = [_]u8{ 'a', 'b', 'c', 'd' };

export const non_utf8 linksection(".custom_section.non-utf8") = [_]u8{ 255, 254, 253 };

export const duplicate_name_1 linksection(".custom_section.dupe-name") = [_]u8{ 'o', 'n', 'e' };
export const duplicate_name_2 linksection(".custom_section.dupe-name") = [_]u8{ 't', 'w', 'o' };

// These should not become wasm custom sections.
export const no_leading_period linksection("custom_section.ignored4") = "...";
export const extra_char_before_first_prefix linksection("x.custom_section.ignored4") = "...";
export const extra_char_after_first_period linksection(".xcustom_section.ignored4") = "...";
export const sections_instead_of_section linksection(".custom_sections.ignored1") = "...";
export const missing_letter_before_last_period linksection(".custom_sectio.ignored2") = "...";
