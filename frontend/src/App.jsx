import { BrowserRouter } from "react-router-dom";
import AppRoutes from "./routes/routes";
import "./assets/styles/index.css";
import { AuthContext, useAuth } from "./contexts/auth.context";
import { CartProvider } from "./contexts/cart.contect";

function App() {
  const { user, toggleUser } = useAuth();

  return (
    <BrowserRouter>
      <AuthContext.Provider value={{ user, toggleUser }}>
        <CartProvider>
          <AppRoutes />
        </CartProvider>
      </AuthContext.Provider>
    </BrowserRouter>
  );
}

export default App;
