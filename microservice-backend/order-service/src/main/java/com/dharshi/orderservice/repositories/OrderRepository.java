package com.dharshi.orderservice.repositories;

import com.dharshi.orderservice.modals.Order;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.Set;

public interface OrderRepository extends MongoRepository<Order,String> {
    java.util.Optional<Order> findByIdAndUserId(String id, String userId);

    Set<Order> findByUserIdOrderByIdDesc(String userId);


}
