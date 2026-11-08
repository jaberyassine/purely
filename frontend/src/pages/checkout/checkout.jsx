
import Header from "../../components/header/header";
import Footer from "../../components/footer/footer";
import "./checkout.css";
import { useForm } from "react-hook-form";

import OrderService from "../../api-service/order.service";
import { useContext, useEffect } from "react";
import CartContext from "../../contexts/cart.contect";
import { Link, useNavigate } from "react-router-dom";

const CheckoutForm = () => {
  const { register, handleSubmit, formState } = useForm();
  const { isLoading, orderError: error, placeOrder } = OrderService();
  const { cart, clearCart } = useContext(CartContext);
  const navigate = useNavigate();

  const onSubmit = async (data) => {
    try {
      await placeOrder(data, cart.cartId);
      clearCart();
      navigate("/order/success");
    } catch (e) {
      // error handling if needed
    }
  };

  return (
    <>
      <Header />
      <main className="checkout-container" id="page-content">
        <h1>Checkout</h1>
        <div className="checkout-wrapper">
          <form onSubmit={handleSubmit(onSubmit)}>
            {error && <small className="text-danger">{error}</small>}
            <div className="input-box">
              <label htmlFor="fname" className="form-label">
                First Name
              </label>
              <input
                type="text"
                className="form-control"
                id="fname"
                placeholder="Eg. John"
                {...register("fname", {
                  required: "First name is required!",
                })}
              />
              {formState.errors.fname && (
                <small className="text-danger">
                  {formState.errors.fname.message}
                </small>
              )}
            </div>
            <div className="input-box">
              <label htmlFor="lname" className="form-label">
                Last Name
              </label>
              <input
                type="text"
                className="form-control"
                id="lname"
                placeholder="Eg. Smith"
                {...register("lname", {
                  required: "Last name is required!",
                })}
              />
              {formState.errors.lname && (
                <small className="text-danger">
                  {formState.errors.lname.message}
                </small>
              )}
            </div>
            <div className="input-box">
              <label htmlFor="address1" className="form-label">
                Address Line 1
              </label>
              <input
                type="text"
                className="form-control"
                id="address1"
                placeholder="Eg. House No, Street No, Area"
                {...register("address1", {
                  required: "Address line 1 is required!",
                })}
              />
              {formState.errors.address1 && (
                <small className="text-danger">
                  {formState.errors.address1.message}
                </small>
              )}
            </div>
            <div className="input-box">
              <label htmlFor="address2" className="form-label">
                Address Line 2
              </label>
              <input
                type="text"
                className="form-control"
                id="address2"
                placeholder="Eg. Suite no / floor No"
                {...register("address2")}
              />
            </div>
            <div className="input-box">
              <label htmlFor="city" className="form-label">
                City
              </label>
              <input
                type="text"
                className="form-control"
                id="city"
                placeholder="Your city"
                {...register("city", {
                  required: "City is required!",
                })}
              />
              {formState.errors.city && (
                <small className="text-danger">
                  {formState.errors.city.message}
                </small>
              )}
            </div>
            <div className="input-box">
              <label htmlFor="phone" className="form-label">
                Phone Number
              </label>
              <input
                type="text"
                className="form-control"
                id="phone"
                placeholder="Your phone number"
                {...register("phone", {
                  required: "Phone is required!",
                })}
              />
              {formState.errors.phone && (
                <small className="text-danger">
                  {formState.errors.phone.message}
                </small>
              )}
            </div>
            <button
              type="submit"
              disabled={isLoading || !cart?.cartItems?.length}
              className={isLoading ? "loading" : ""}
              name="proceed"
            >
              {isLoading ? "Processing..." : "Place Order"}
            </button>
          </form>
          <summary>
            <h2>Order summary</h2>
            <hr />
            {cart?.cartItems.map((cartItem) => (
              <div className="product" key={cartItem.productId}>
                <img src={`${cartItem.imageUrl}`} alt={cartItem.productName} />
                <div className="product-info">
                  <h4>{cartItem.productName}</h4>
                  <span className="product-price">
                    {cartItem.price} x {cartItem.quantity} = Rs.{" "}
                    {parseFloat(cartItem.amount).toFixed(2)}
                  </span>
                </div>
              </div>
            ))}
            <hr />
            <h3>
              <span>Sub Total</span>
              <span>Rs. {parseFloat(cart?.subtotal).toFixed(2)}</span>
            </h3>
            <br />
            <small>
              This is a demo order. No payment or physical delivery is arranged.
            </small>
            <br />
            <Link to="/">
              <button>Edit cart</button>
            </Link>
          </summary>
        </div>
      </main>
      <Footer />
    </>
  );
};

export default CheckoutForm;
