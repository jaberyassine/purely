package com.dharshi.orderservice.services;

import com.dharshi.orderservice.enums.EOrderStatus;
import com.dharshi.orderservice.exceptions.ResourceNotFoundException;
import com.dharshi.orderservice.modals.Order;
import com.dharshi.orderservice.repositories.OrderRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.Optional;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class OrderOwnershipTest {
    private final OrderRepository repository = mock(OrderRepository.class);
    private final OrderServiceImpl service = new OrderServiceImpl();
    @BeforeEach void setup() { ReflectionTestUtils.setField(service, "orderRepository", repository); }
    @Test void anotherUsersOrderCannotBeCancelled() {
        when(repository.findByIdAndUserId("order", "other")).thenReturn(Optional.empty());
        assertThrows(ResourceNotFoundException.class, () -> service.cancelOrder("order", "other"));
        verify(repository, never()).save(any(Order.class));
        verify(repository, never()).findById(anyString());
    }
    @Test void ownerCanCancelOrder() throws Exception {
        var order = Order.builder().id("order").userId("owner").orderStatus(EOrderStatus.PENDING).build();
        when(repository.findByIdAndUserId("order", "owner")).thenReturn(Optional.of(order));
        assertTrue(service.cancelOrder("order", "owner").getBody().isSuccess());
        assertEquals(EOrderStatus.CANCELLED, order.getOrderStatus());
        verify(repository).save(order);
    }
}
