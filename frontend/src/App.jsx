import "./assets/styles/index.css";
import "./assets/styles/storefront.css";
import { BrowserRouter, useLocation } from "react-router-dom";
import { useEffect } from "react";
import AppRoutes from "./routes/routes";
import { AuthContext, useAuth } from "./contexts/auth.context";
import { CartProvider } from "./contexts/cart.contect";

function App() {
  const { user, toggleUser } = useAuth();

  return (
    <BrowserRouter>
      <ScrollPosition />
      <AuthContext.Provider value={{ user, toggleUser }}>
        <CartProvider>
          <AppRoutes />
        </CartProvider>
      </AuthContext.Provider>
    </BrowserRouter>
  );
}

export default App;

function ScrollPosition() {
  const { pathname, hash } = useLocation();
  useEffect(() => {
    if (!hash) { window.scrollTo(0, 0); return; }
    const timer = setTimeout(() => document.getElementById(hash.slice(1))?.scrollIntoView(), 100);
    return () => clearTimeout(timer);
  }, [pathname, hash]);
  return null;
}
