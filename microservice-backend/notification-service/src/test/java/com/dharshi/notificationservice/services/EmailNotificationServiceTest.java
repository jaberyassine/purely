package com.dharshi.notificationservice.services;

import com.dharshi.notificationservice.dtos.MailRequestDto;
import jakarta.mail.Session;
import jakarta.mail.internet.MimeMessage;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mail.MailSendException;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.Properties;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class EmailNotificationServiceTest {
    private JavaMailSender sender;
    private EmailNotificationService service;
    private MimeMessage message;

    @BeforeEach void setup() {
        sender = mock(JavaMailSender.class);
        service = new EmailNotificationService();
        ReflectionTestUtils.setField(service, "javaMailSender", sender);
        ReflectionTestUtils.setField(service, "fromMail", "sender@example.invalid");
        message = new MimeMessage(Session.getInstance(new Properties()));
        when(sender.createMimeMessage()).thenReturn(message);
    }

    @Test void successfulDeliveryReturnsSuccessAndPreservesMailContent() throws Exception {
        var result = service.sendEmail(new MailRequestDto("recipient@example.invalid", "Order confirmed", "<b>Confirmed</b>"));
        assertEquals(200, result.getStatusCode().value());
        assertNotNull(result.getBody());
        assertTrue(result.getBody().isSuccess());
        assertEquals("Successfully sent email!", result.getBody().getResponse());
        verify(sender).send(message);
        assertEquals("Order confirmed", message.getSubject());
        assertEquals("recipient@example.invalid", message.getAllRecipients()[0].toString());
        assertEquals("<b>Confirmed</b>", message.getContent());
    }

    @Test void failedDeliveryReturnsFailureWithoutExposingProviderDetails() {
        doThrow(new MailSendException("internal transport detail")).when(sender).send(message);
        var result = service.sendEmail(new MailRequestDto("recipient@example.invalid", "Order confirmed", "Confirmed"));
        assertEquals(500, result.getStatusCode().value());
        assertNotNull(result.getBody());
        assertFalse(result.getBody().isSuccess());
        assertEquals("Unable to send email!", result.getBody().getResponse());
        verify(sender).send(message);
    }
}
