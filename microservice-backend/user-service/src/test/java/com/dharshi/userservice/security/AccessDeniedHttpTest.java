package com.dharshi.userservice.security;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.context.WebApplicationContext;
import tools.jackson.databind.json.JsonMapper;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.MOCK)
@ActiveProfiles("test")
@Import(AccessDeniedHttpTest.AdminEndpoint.class)
class AccessDeniedHttpTest {
    @Autowired WebApplicationContext context;
    private MockMvc mvc;

    @BeforeEach void setup() {
        mvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
    }

    // Test-only endpoint exercises the real filter chain and method authorization.
    @RestController
    static class AdminEndpoint {
        @GetMapping("/test-support/admin-route")
        @PreAuthorize("hasAuthority('ROLE_ADMIN')")
        public String administratorOnly() { return "allowed"; }
    }

    @Test void authenticatedNonAdminReceivesJson403WithoutErrorRedispatch() throws Exception {
        var response = mvc.perform(get("/test-support/admin-route")
                .with(user("ordinary-user").authorities(() -> "ROLE_USER")))
                .andReturn().getResponse();
        assertEquals(403, response.getStatus());
        assertEquals("application/json", response.getContentType());
        assertNull(response.getErrorMessage(), "sendError would trigger an ERROR redispatch");
        var body = JsonMapper.builder().build().readTree(response.getContentAsString());
        assertEquals(403, body.path("status").asInt());
        assertEquals("Forbidden", body.path("error").asText());
    }

    @Test void anonymousRequestIsUnauthenticated() throws Exception {
        assertEquals(401, mvc.perform(get("/test-support/admin-route"))
                .andReturn().getResponse().getStatus());
    }

    @Test void administratorCanReachTheProtectedEndpoint() throws Exception {
        var response = mvc.perform(get("/test-support/admin-route")
                .with(user("administrator").authorities(() -> "ROLE_ADMIN")))
                .andReturn().getResponse();
        assertEquals(200, response.getStatus());
        assertEquals("allowed", response.getContentAsString());
    }
}
