package com.dharshi.userservice.dtos;

import lombok.Builder;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import lombok.Data;

@Builder
@NoArgsConstructor
@AllArgsConstructor
@Data
public class UserDto {
    private String userId;
    private String email;
    private String username;
}
