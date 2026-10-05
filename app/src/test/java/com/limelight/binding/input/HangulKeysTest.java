package com.limelight.binding.input;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public class HangulKeysTest {
    @Test
    public void typesSyllablesAndJamo() {
        assertEquals("dkssud", HangulKeys.keys("안녕"));
        assertEquals("gkfn", HangulKeys.keys("하루"));
        assertEquals("rkqt", HangulKeys.keys("값"));
        assertEquals("dhk", HangulKeys.keys("와"));
        assertEquals("Rkf", HangulKeys.keys("깔"));
        assertEquals("d", HangulKeys.keys("ㅇ"));
        assertEquals("sj", HangulKeys.keys("ㄴㅓ"));
        assertEquals("nl", HangulKeys.keys("ㅟ"));
        assertEquals("gl", HangulKeys.keys("히"));
    }

    @Test
    public void typesLatinDigitsAndSpace() {
        assertEquals("Hi 2\n", HangulKeys.keys("Hi 2\n"));
    }

    @Test
    public void rejectsOtherCharacters() {
        assertNull(HangulKeys.keys("안녕!"));
        assertNull(HangulKeys.keys("日"));
    }
}
