package com.dharshi.authservice.security.jwt;

import com.dharshi.authservice.security.UserDetailsImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;

class JwtUtilsTest {
    private final JwtUtils jwt = new JwtUtils();
    @BeforeEach
    void setup() {
        ReflectionTestUtils.setField(jwt, "jwtSecret", "dGVzdC1vbmx5LXNlY3JldC0zMi1ieXRlcy1taW5pbXVtISE=");
        ReflectionTestUtils.setField(jwt, "jwtExpirationMs", 60000);
    }
    private String token() {
        var user = new UserDetailsImpl("1", "demo", "demo@example.invalid", "unused", List.of(), true);
        return jwt.generateJwtToken(new UsernamePasswordAuthenticationToken(user, null, List.of()));
    }
    @Test
    void issuedTokenPreservesIdentity() {
        String token = token();
        assertTrue(jwt.validateJwtToken(token));
        assertEquals("demo@example.invalid", jwt.getUserNameFromJwtToken(token));
    }
    @Test
    void tamperedSignatureIsRejectedWithoutEscapingValidation() {
        String token = token();
        int start = token.lastIndexOf('.') + 1;
        char replacement = token.charAt(start) == 'A' ? 'B' : 'A';
        String tampered = token.substring(0, start) + replacement + token.substring(start + 1);
        assertFalse(jwt.validateJwtToken(tampered));
    }
    @Test
    void expiredTokenIsRejected() {
        ReflectionTestUtils.setField(jwt, "jwtExpirationMs", -60000);
        assertFalse(jwt.validateJwtToken(token()));
    }
}
