package com.dharshi.categoryservice.security;

import com.dharshi.categoryservice.dtos.ApiResponseDto;
import com.dharshi.categoryservice.feigns.AuthService;
import com.dharshi.categoryservice.services.CategoryService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import tools.jackson.databind.json.JsonMapper;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.MOCK)
@ActiveProfiles("test")
class AuthorizationHttpTest {
    @Autowired WebApplicationContext context;
    @MockitoBean AuthService authService;
    @MockitoBean CategoryService categoryService;
    private MockMvc mvc;

    @BeforeEach void setup() throws Exception {
        mvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
        when(categoryService.createCategory(any())).thenReturn(ResponseEntity.ok(
                ApiResponseDto.builder().isSuccess(true).message("created").build()));
    }
    private MockHttpServletResponse createCategory(String token) throws Exception {
        var request = post("/admin/category/create").contentType("application/json")
                .content("{\"name\":\"fixture\",\"description\":\"test\",\"imageUrl\":\"fixture.png\"}");
        if (token != null) request.header("Authorization", "Bearer " + token);
        return mvc.perform(request).andReturn().getResponse();
    }
    private void identity(String token, String role) {
        when(authService.validateToken(token)).thenReturn(ResponseEntity.ok(
                ApiResponseDto.<UserDetails>builder().isSuccess(true)
                        .response(new UserDetails("fixture-user", List.of(role))).build()));
    }
    @Test void ordinaryUserReceivesJson403WithoutErrorRedispatch() throws Exception {
        identity("user-token", "ROLE_USER");
        var response = createCategory("user-token");
        assertEquals(403, response.getStatus());
        assertNull(response.getErrorMessage(), "Do not call sendError and trigger an ERROR redispatch");
        assertEquals(403, JsonMapper.builder().build().readTree(response.getContentAsString()).path("status").asInt());
        verify(categoryService, never()).createCategory(any());
    }
    @Test void anonymousUserStillReceives401() throws Exception {
        assertEquals(401, createCategory(null).getStatus());
        verifyNoInteractions(authService);
        verify(categoryService, never()).createCategory(any());
    }
    @Test void administratorCanCreateCategory() throws Exception {
        identity("admin-token", "ROLE_ADMIN");
        var response = createCategory("admin-token");
        assertEquals(200, response.getStatus());
        assertTrue(JsonMapper.builder().build().readTree(response.getContentAsString()).path("success").asBoolean());
        verify(categoryService).createCategory(any());
    }
}
