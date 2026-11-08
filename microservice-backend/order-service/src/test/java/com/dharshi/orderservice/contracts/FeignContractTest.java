package com.dharshi.orderservice.contracts;

import com.dharshi.orderservice.dtos.ApiResponseDto;
import feign.Request;
import feign.Response;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.beans.factory.support.DefaultListableBeanFactory;
import org.springframework.boot.http.converter.autoconfigure.ClientHttpMessageConvertersCustomizer;
import org.springframework.cloud.openfeign.support.*;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;
import tools.jackson.databind.json.JsonMapper;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.stream.Stream;
import static org.junit.jupiter.api.Assertions.*;

class FeignContractTest {
    static Stream<Arguments> payloads() {
        return Stream.of(
            Arguments.of(com.dharshi.orderservice.feigns.AuthService.class, "validateToken", "{\"success\":true,\"message\":\"Fixture\",\"response\":{\"userId\":\"user-1\",\"authorities\":[\"ROLE_USER\"]}}", "getUserId", "user-1"),
            Arguments.of(com.dharshi.orderservice.feigns.CartService.class, "getCartById", "{\"success\":true,\"message\":\"Fixture\",\"response\":{\"cartId\":\"cart-1\",\"subtotal\":25,\"userId\":\"user-1\",\"noOfCartItems\":1,\"cartItems\":[{\"price\":25,\"productName\":\"Fixture\",\"amount\":25,\"quantity\":1,\"categoryName\":\"Fixture category\",\"imageUrl\":\"fixture.png\",\"productId\":\"product-1\"}]}}", "getCartId", "cart-1"),
            Arguments.of(com.dharshi.orderservice.feigns.CartService.class, "clearCartById", "{\"success\":true,\"message\":\"Fixture\",\"response\":null}", "null", ""),
            Arguments.of(com.dharshi.orderservice.feigns.NotificationService.class, "sendEmail", "{\"success\":true,\"message\":\"Fixture\",\"response\":null}", "null", ""),
            Arguments.of(com.dharshi.orderservice.feigns.UserService.class, "getUserById", "{\"success\":true,\"message\":\"Fixture\",\"response\":{\"username\":\"fixture\",\"email\":\"fixture@example.invalid\",\"userId\":\"user-1\"}}", "getUserId", "user-1")
        );
    }
    @ParameterizedTest
    @MethodSource("payloads")
    void realFeignDecoderReadsServiceResponse(Class<?> client, String methodName,
            String json, String getter, String expected) throws Exception {
        var beans = new DefaultListableBeanFactory();
        var converters = new FeignHttpMessageConverters(
                beans.getBeanProvider(ClientHttpMessageConvertersCustomizer.class),
                beans.getBeanProvider(HttpMessageConverterCustomizer.class));
        beans.registerSingleton("converters", converters);
        var decoder = new ResponseEntityDecoder(new SpringDecoder(
                beans.getBeanProvider(FeignHttpMessageConverters.class)));
        var method = Arrays.stream(client.getMethods())
                .filter(candidate -> candidate.getName().equals(methodName)).findFirst().orElseThrow();
        var request = Request.create(Request.HttpMethod.GET, "http://fixture.local/test",
                Map.of(), null, StandardCharsets.UTF_8, null);
        var response = Response.builder().request(request).status(200).reason("OK")
                .headers(Map.of("Content-Type", List.of("application/json")))
                .body(json, StandardCharsets.UTF_8).build();
        var decoded = (ResponseEntity<?>) decoder.decode(response, method.getGenericReturnType());
        var body = (ApiResponseDto<?>) decoded.getBody();
        assertNotNull(body);
        assertTrue(body.isSuccess());
        var payload = body.getResponse();
        if (getter.equals("boolean")) assertEquals(Boolean.TRUE, payload);
        else if (getter.equals("null")) assertNull(payload);
        else {
            assertNotNull(payload);
            assertEquals(expected, ReflectionTestUtils.invokeMethod(payload, getter));
        }
        if (methodName.equals("getCartById")) {
            var items = (Set<?>) ReflectionTestUtils.invokeMethod(payload, "getCartItems");
            assertEquals(1, items.size());
            var quantity = (Integer) ReflectionTestUtils.invokeMethod(items.iterator().next(), "getQuantity");
            assertEquals(1, quantity.intValue());
        }
        var encoded = JsonMapper.builder().build().writeValueAsString(body);
        assertTrue(encoded.contains("\"success\":true"));
        assertFalse(encoded.contains("\"isSuccess\""));
    }

    @Test void successWireNameIsStableWithCompilerParameterMetadata() throws Exception {
        var constructor = ApiResponseDto.class.getConstructor(boolean.class, String.class, Object.class);
        assertTrue(constructor.getParameters()[0].isNamePresent(), "Compile contracts with -parameters, like Maven");
        var mapper = JsonMapper.builder().build();
        var denied = mapper.readValue("{\"success\":false,\"message\":\"denied\",\"response\":null}", ApiResponseDto.class);
        assertFalse(denied.isSuccess());
        assertThrows(Exception.class, () -> mapper.readValue("{\"isSuccess\":true,\"message\":\"invalid wire name\",\"response\":null}", ApiResponseDto.class));
    }
}
