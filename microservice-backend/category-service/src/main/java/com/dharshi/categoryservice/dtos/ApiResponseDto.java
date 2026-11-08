package com.dharshi.categoryservice.dtos;

import lombok.Builder;
import lombok.NoArgsConstructor;
import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

@Data
@Builder
@NoArgsConstructor
public class ApiResponseDto<T> {
    @JsonProperty("success")
    private boolean isSuccess;
    private String message;
    private T response;

    @JsonCreator(mode = JsonCreator.Mode.PROPERTIES)
    public ApiResponseDto(@JsonProperty(value = "success", required = true) boolean isSuccess,
                          @JsonProperty("message") String message,
                          @JsonProperty("response") T response) {
        this.isSuccess = isSuccess;
        this.message = message;
        this.response = response;
    }
}
