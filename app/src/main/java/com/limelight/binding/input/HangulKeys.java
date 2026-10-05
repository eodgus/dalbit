package com.limelight.binding.input;

/**
 * Converts text to the keys typing it on a Korean 2-set (dubeolsik) layout, so text an on-screen
 * IME composed can be retyped on the host and composed there by its own IME.
 */
public class HangulKeys {
    private static final String[] INITIALS = {
            "r", "R", "s", "e", "E", "f", "a", "q", "Q", "t", "T", "d", "w", "W", "c", "z", "x", "v", "g"
    };
    private static final String[] VOWELS = {
            "k", "o", "i", "O", "j", "p", "u", "P", "h", "hk", "ho", "hl", "y", "n", "nj", "np", "nl", "b", "m", "ml", "l"
    };
    private static final String[] FINALS = {
            "", "r", "R", "rt", "s", "sw", "sg", "e", "f", "fr", "fa", "fq", "ft", "fx", "fv", "fg",
            "a", "q", "qt", "t", "T", "d", "w", "c", "z", "x", "v", "g"
    };
    // Compatibility jamo U+3131..U+3163
    private static final String[] JAMO = {
            "r", "R", "rt", "s", "sw", "sg", "e", "E", "f", "fr", "fa", "fq", "ft", "fx", "fv", "fg",
            "a", "q", "Q", "qt", "t", "T", "d", "w", "W", "c", "z", "x", "v", "g",
            "k", "o", "i", "O", "j", "p", "u", "P", "h", "hk", "ho", "hl", "y", "n", "nj", "np", "nl", "b", "m", "ml", "l"
    };

    /** Keys typing one character, or null if it can't be typed this way. */
    public static String keys(char c) {
        if (c >= 0xAC00 && c <= 0xD7A3) {
            int code = c - 0xAC00;
            return INITIALS[code / 588] + VOWELS[code % 588 / 28] + FINALS[code % 28];
        }
        if (c >= 0x3131 && c <= 0x3163) {
            return JAMO[c - 0x3131];
        }
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == ' ' || c == '\n') {
            return String.valueOf(c);
        }
        return null;
    }

    /** Keys typing the text, or null if some character can't be typed this way. */
    public static String keys(CharSequence text) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < text.length(); i++) {
            String k = keys(text.charAt(i));
            if (k == null) {
                return null;
            }
            sb.append(k);
        }
        return sb.toString();
    }
}
