package com.dharshi.cartservice.dtos;

import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;
import lombok.Data;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class CartItemRequestDto {
    private String productId;
    private int quantity;
}
