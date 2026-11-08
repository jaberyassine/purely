package com.dharshi.productservice.services;

import com.dharshi.productservice.exceptions.ServiceLogicException;
import com.dharshi.productservice.repositories.ProductRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class ProductServiceTest {
    private final ProductRepository repository = mock(ProductRepository.class);
    private final ProductServiceImpl service = new ProductServiceImpl();

    @BeforeEach
    void setup() { ReflectionTestUtils.setField(service, "productRepository", repository); }

    @Test
    void emptyCatalogIsSuccessfulWithAnEmptyList() throws Exception {
        when(repository.findAll()).thenReturn(List.of());
        var response = service.getAllProducts();
        assertEquals(200, response.getStatusCode().value());
        assertNotNull(response.getBody());
        assertEquals(List.of(), response.getBody().getResponse());
    }

    @Test
    void databaseFailureDoesNotReturnASuccessfulEmptyCatalog() {
        when(repository.findAll()).thenThrow(new RuntimeException("database unavailable"));
        assertThrows(ServiceLogicException.class, service::getAllProducts);
    }
}
