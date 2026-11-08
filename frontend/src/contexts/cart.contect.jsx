import React, { createContext, useState, useEffect } from "react";
import API_BASE_URL from "../api-service/apiConfig";
import axios from "axios";

const CartContext = createContext();

export const CartProvider = ({ children }) => {
  const [cart, setCart] = useState({
    cartItems: [],
    subtotal: 0,
    cartId: null,
  });
  const [cartError, setError] = useState(false);
  const [isProcessingCart, setProcessing] = useState(false);
  const user = JSON.parse(localStorage.getItem("user"));

  const authHeader = () => {
    return { Authorization: `Bearer ${user?.token}` };
  };

  const addItemToCart = async (productId, quantity) => {
    setProcessing(true);
    let success = false;
    await axios
      .post(
        `${API_BASE_URL}/cart-service/cart/add`,
        { productId, quantity },
        { headers: authHeader() }
      )
      .then(() => {
        setError(false);
        success = true;
      })
      .catch(() => {
        setError(true);
      });
    setProcessing(false);
    await getCartInformation();
    return success;
  };

  const updateItemQuantity = async (productId, quantity) => {
    setProcessing(true);
    await axios
      .post(
        `${API_BASE_URL}/cart-service/cart/add`,
        { productId, quantity },
        { headers: authHeader() }
      )
      .then(() => {
        setError(false);
      })
      .catch(() => {
        setError(true);
      });
    setProcessing(false);
    getCartInformation();
  };

  const removeItemFromCart = async (productId) => {
    setProcessing(true);
    await axios
      .delete(`${API_BASE_URL}/cart-service/cart/remove`, {
        headers: authHeader(),
        params: { productId: productId },
      })
      .then(() => {
        setError(false);
      })
      .catch(() => {
        setError(true);
      });
    getCartInformation();
  };

  const getCartInformation = async () => {
    if (!user?.token) {
      setCart({ cartItems: [], subtotal: 0, cartId: null });
      setError(false);
      return;
    }
    setProcessing(true);
    await axios
      .get(`${API_BASE_URL}/cart-service/cart/get/byUser`, {
        headers: authHeader(),
      })
      .then((response) => {
        setError(false);
        setCart(response.data.response);
      })
      .catch(() => {
        setCart({ cartItems: [], subtotal: 0, cartId: null });
        setError(true);
      });
    setProcessing(false);
  };

  const clearCart = () => {
    setCart({ cartItems: [], subtotal: 0, cartId: null });
  };

  useEffect(() => {
    getCartInformation();
  }, []);

  return (
    <CartContext.Provider
      value={{
        cart,
        cartError,
        isProcessingCart,
        addItemToCart,
        updateItemQuantity,
        removeItemFromCart,
        getCartInformation,
        setCart,
        clearCart,
      }}
    >
      {children}
    </CartContext.Provider>
  );
};

export default CartContext;
