import { useEffect, useState } from "react";
import API_BASE_URL from "./apiConfig";
import axios from "axios";
import { useNavigate } from "react-router-dom";

function OrderService() {
  const [orderError, setError] = useState(null);
  const [isLoading, setLoading] = useState(false);
  const [userOrders, setUserOrders] = useState([]);
  const user = JSON.parse(localStorage.getItem("user"));
  const navigate = useNavigate();

  const authHeader = () => {
    return { Authorization: `Bearer ${user?.token}` };
  };

  const placeOrder = async (
    { fname, lname, address1, address2, city, phone },
    cart
  ) => {
    setLoading(true);
    await axios
      .post(
        `${API_BASE_URL}/order-service/order/create`,
        {
          firstName: fname,
          lastName: lname,
          addressLine1: address1,
          addressLine2: address2,
          city: city,
          phoneNo: phone,
          cartId: cart,
        },
        { headers: authHeader() }
      )
      .then((response) => {
        if (!response.data.success) throw new Error('Order was not accepted');
        setError(null);
        // Removed redirect after order placement
      })
      .catch((error) => {
        setError('Your order could not be placed. Your bag has been kept; please try again.');
        throw new Error('Order was not placed');
      });

    setLoading(false);
  };

  const getOrdersByUser = async () => {
    setLoading(true);
    await axios
      .get(`${API_BASE_URL}/order-service/order/get/byUser`, {
        headers: authHeader(),
      })
      .then((response) => {
        setError(null);
        setUserOrders(response.data.response);
      })
      .catch((error) => {
        setUserOrders([]);
      });
    setLoading(false);
  };

  useEffect(() => {
    getOrdersByUser();
  }, []);

  return { isLoading, orderError, userOrders, getOrdersByUser, placeOrder };
}

export default OrderService;
