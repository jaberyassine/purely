package com.dharshi.productservice.dtos;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import lombok.Builder;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import lombok.Data;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

@Data
@JsonIgnoreProperties(ignoreUnknown = true)
@Document(collection = "categories")
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CategoryDto {

    @Id
    private String id;

    private String categoryName;

}
