package com.dharshi.authservice.services;

import com.dharshi.authservice.dtos.SignUpRequestDto;
import com.dharshi.authservice.enums.ERole;
import com.dharshi.authservice.factories.RoleFactory;
import com.dharshi.authservice.modals.Role;
import com.dharshi.authservice.modals.User;
import com.dharshi.authservice.repositories.UserRepository;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class RegistrationSecurityTest {
    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void publicRegistrationOnlyGrantsUserRole(boolean requestsAdmin) throws Exception {
        var service = new AuthServiceImpl();
        var repository = mock(UserRepository.class);
        var roles = mock(RoleFactory.class);
        var encoder = mock(PasswordEncoder.class);
        var userRole = new Role("user-role", ERole.ROLE_USER);
        ReflectionTestUtils.setField(service, "userRepository", repository);
        ReflectionTestUtils.setField(service, "roleFactory", roles);
        ReflectionTestUtils.setField(service, "passwordEncoder", encoder);
        when(roles.getInstance("user")).thenReturn(userRole);
        when(encoder.encode("test-password")).thenReturn("encoded-password");
        when(repository.insert(any(User.class))).thenAnswer(call -> call.getArgument(0));
        var request = new SignUpRequestDto("test-user", "test@example.invalid", "test-password");
        if (requestsAdmin) request.setRoles(Set.of("admin"));

        assertEquals(201, service.registerUser(request).getStatusCode().value());
        var captured = ArgumentCaptor.forClass(User.class);
        verify(repository).insert(captured.capture());
        assertEquals(Set.of(userRole), captured.getValue().getRoles());
        assertEquals("encoded-password", captured.getValue().getPassword());
        verify(roles, never()).getInstance("admin");
    }
}
