package com.dharshi.authservice;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import com.dharshi.authservice.repositories.RoleRepository;

@SpringBootTest
@ActiveProfiles("test")
class AuthServiceApplicationTests {

    // Keep context/role-seeder wiring covered without touching a real database.
    @MockitoBean
    private RoleRepository roleRepository;

	@Test
	void contextLoads() {
	}

}
