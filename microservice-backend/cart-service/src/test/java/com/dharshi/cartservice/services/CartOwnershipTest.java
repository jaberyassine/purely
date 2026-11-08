package com.dharshi.cartservice.services;

import com.dharshi.cartservice.exceptions.ResourceNotFoundException;
import com.dharshi.cartservice.modals.Cart;
import com.dharshi.cartservice.repositories.CartRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.HashSet;
import java.util.Optional;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class CartOwnershipTest {
    private final CartRepository repository = mock(CartRepository.class);
    private final CartServiceImpl service = new CartServiceImpl();
    @BeforeEach void setup() { ReflectionTestUtils.setField(service, "cartRepository", repository); }
    @Test void anotherUsersCartCannotBeRead() {
        when(repository.findByIdAndUserId("cart", "other")).thenReturn(Optional.empty());
        assertThrows(ResourceNotFoundException.class, () -> service.getCartById("cart", "other"));
        verify(repository, never()).findById(anyString());
    }
    @Test void anotherUsersCartCannotBeCleared() {
        when(repository.findByIdAndUserId("cart", "other")).thenReturn(Optional.empty());
        assertThrows(ResourceNotFoundException.class, () -> service.clearCartById("cart", "other"));
        verify(repository, never()).save(any(Cart.class));
    }
    @Test void ownerCanReadCart() throws Exception {
        var cart = Cart.builder().id("cart").userId("owner").cartItems(new HashSet<>()).build();
        when(repository.findByIdAndUserId("cart", "owner")).thenReturn(Optional.of(cart));
        assertTrue(service.getCartById("cart", "owner").getBody().isSuccess());
    }
    @Test void ownerCanClearCart() throws Exception {
        var cart = Cart.builder().id("cart").userId("owner").cartItems(new HashSet<>()).build();
        when(repository.findByIdAndUserId("cart", "owner")).thenReturn(Optional.of(cart));
        assertTrue(service.clearCartById("cart", "owner").getBody().isSuccess());
        verify(repository).save(cart);
    }
}
