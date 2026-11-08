package com.dharshi.cartservice.repositories;


import com.dharshi.cartservice.modals.Cart;
import org.springframework.data.mongodb.repository.MongoRepository;

public interface CartRepository extends MongoRepository<Cart, String> {
    java.util.Optional<Cart> findByIdAndUserId(String id, String userId);
    Cart findByUserId(String userId);
    boolean existsByUserId(String userId);

}
