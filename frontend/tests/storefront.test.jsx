import React from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, cleanup, fireEvent, render, renderHook, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom';
import axios from 'axios';
import { AuthContext } from '../src/contexts/auth.context';
import CartContext, { CartProvider } from '../src/contexts/cart.contect';
import ProductGrid, { ProductCard } from '../src/components/product-grid/product-grid';
import Cart from '../src/components/cart/cart';
import Header from '../src/components/header/header';
import Categories, { categoryImage } from '../src/components/categories/categories';
import Featured from '../src/components/featured/featured';
import Products, { CatalogView } from '../src/pages/products/products';
import Home from '../src/pages/home/home';
import useCatalog from '../src/hooks/useCatalog';
import { selectProducts } from '../src/lib/catalog.mjs';
import OrderService from '../src/api-service/order.service';
import CheckoutForm from '../src/pages/checkout/checkout';
import App from '../src/App';

vi.mock('axios', () => ({ default: { get: vi.fn(), post: vi.fn(), delete: vi.fn() } }));

const categories = [
  { id: 'fitness', categoryName: 'Fitness Equipment', imageUrl: 'fitness.jpg' },
  { id: 'care', categoryName: 'Personal Care', imageUrl: '/categories/care.jpg' },
];
const products = [
  { id: 'mat', productName: 'Yoga Mat', categoryId: 'fitness', categoryName: 'Fitness Equipment', price: 25, imageUrl: 'https://example.invalid/mat.jpg', description: 'Movement' },
  { id: 'cream', productName: 'Face Moisturizer', categoryId: 'care', categoryName: 'Personal Care', price: 8, imageUrl: 'https://example.invalid/cream.jpg', description: 'Everyday care' },
  { id: 'ring', productName: 'Pilates Ring', categoryId: 'fitness', categoryName: 'Fitness Equipment', price: 22, imageUrl: '', description: 'Movement' },
];
const emptyCart = { cartItems: [], subtotal: 0, noOfCartItems: 0, cartId: null };
const signedIn = { token: 'unit-test-only' };
let cartValue;
let authValue;

function Location() {
  const location = useLocation();
  return <span data-testid="location">{location.pathname}</span>;
}
function mount(ui, { user = signedIn, cart = {}, path = '/' } = {}) {
  authValue = { user, toggleUser: vi.fn() };
  cartValue = {
    cart: emptyCart, cartError: false, isProcessingCart: false,
    addItemToCart: vi.fn().mockResolvedValue(true), removeItemFromCart: vi.fn(),
    getCartInformation: vi.fn().mockResolvedValue(), clearCart: vi.fn(), ...cart,
  };
  return render(<MemoryRouter initialEntries={[path]}>
    <AuthContext.Provider value={authValue}><CartContext.Provider value={cartValue}>
      {ui}<Location />
    </CartContext.Provider></AuthContext.Provider>
  </MemoryRouter>);
}
function catalogResponse(url) {
  const response = url.includes('category-service') ? categories : products;
  return Promise.resolve({ data: { success: true, response } });
}
beforeEach(() => {
  localStorage.clear();
  axios.get.mockReset().mockImplementation(catalogResponse);
  axios.post.mockReset().mockResolvedValue({ data: { success: true } });
  axios.delete.mockReset().mockResolvedValue({ data: { success: true } });
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

describe('product selection', () => {
  it('sorts names and prices without changing the API collection', () => {
    expect(selectProducts(products, categories, { sort: 'name' }).map(p => p.id)).toEqual(['cream', 'ring', 'mat']);
    expect(selectProducts(products, categories, { sort: 'low' }).map(p => p.price)).toEqual([8, 22, 25]);
    expect(selectProducts(products, categories, { sort: 'high' }).map(p => p.price)).toEqual([25, 22, 8]);
    expect(products.map(p => p.id)).toEqual(['mat', 'cream', 'ring']);
  });
  it('handles refreshed category URLs, missing categories and normalized search', () => {
    expect(selectProducts(products, categories, { category: 'Fitness Equipment' })).toHaveLength(2);
    expect(selectProducts(products, categories, { category: 'missing' })).toEqual([]);
    expect(selectProducts(products, categories, { searchTerm: '  PERSONAL CARE ' }).map(p => p.id)).toEqual(['cream']);
    expect(selectProducts(products, categories, { searchTerm: 'missing' })).toEqual([]);
    expect(selectProducts(products, categories)).toHaveLength(3);
  });
});

describe('catalog requests', () => {
  it('loads both resources and stops loading', async () => {
    const { result } = renderHook(() => useCatalog());
    expect(result.current.loading).toBe(true);
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.products).toEqual(products);
    expect(result.current.categories).toEqual(categories);
    expect(result.current.error).toBe(false);
  });
  it('treats a rejected connection as an error', async () => {
    axios.get.mockRejectedValue(new Error('Unavailable'));
    const { result } = renderHook(() => useCatalog());
    await waitFor(() => expect(result.current.error).toBe(true));
    expect(result.current.products).toEqual([]);
    expect(result.current.loading).toBe(false);
  });
  it('rejects unsuccessful API envelopes', async () => {
    axios.get.mockResolvedValue({ data: { success: false } });
    const { result } = renderHook(() => useCatalog());
    await waitFor(() => expect(result.current.error).toBe(true));
  });
  it('handles empty API collections', async () => {
    axios.get.mockResolvedValue({ data: { success: true } });
    const { result } = renderHook(() => useCatalog());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.products).toEqual([]);
    expect(result.current.categories).toEqual([]);
  });
  it('aborts pending requests when the page unmounts', async () => {
    axios.get.mockImplementation(() => new Promise(() => {}));
    const { unmount } = renderHook(() => useCatalog());
    const signal = axios.get.mock.calls[0][1].signal;
    expect(signal.aborted).toBe(false);
    unmount();
    expect(signal.aborted).toBe(true);
  });
});

describe('product cards', () => {
  it('shows the actual photo, name and two-decimal price', () => {
    mount(<ProductCard product={products[0]} />);
    expect(screen.getByRole('img', { name: 'Yoga Mat' }).getAttribute('src')).toBe(products[0].imageUrl);
    expect(screen.getByRole('heading', { name: 'Yoga Mat' })).toBeTruthy();
    expect(screen.getByText('25.00', { exact: false })).toBeTruthy();
  });
  it('redirects anonymous shoppers to sign-in without a cart write', async () => {
    mount(<ProductCard product={products[0]} />, { user: null });
    await userEvent.click(screen.getByRole('button', { name: 'Add to bag: Yoga Mat' }));
    expect(screen.getByTestId('location').textContent).toBe('/auth/login');
    expect(cartValue.addItemToCart).not.toHaveBeenCalled();
  });
  it('disables add while pending and announces success', async () => {
    let resolveAdd;
    const addItemToCart = vi.fn(() => new Promise(resolve => { resolveAdd = resolve; }));
    mount(<ProductCard product={products[0]} />, { cart: { addItemToCart } });
    await userEvent.click(screen.getByRole('button', { name: 'Add to bag: Yoga Mat' }));
    expect(screen.getByRole('button', { name: 'Adding Yoga Mat' }).disabled).toBe(true);
    await act(async () => resolveAdd(true));
    expect(screen.getByRole('status').textContent).toBe('Added to your bag');
    expect(addItemToCart).toHaveBeenCalledWith('mat', 1);
    expect(screen.getByRole('button', { name: 'Add to bag: Yoga Mat' }).disabled).toBe(false);
  });
  it.each([false, 'throw'])('reports a failed add (%s) without claiming success', async outcome => {
    const addItemToCart = outcome === 'throw' ? vi.fn().mockRejectedValue(new Error('Unavailable')) : vi.fn().mockResolvedValue(false);
    mount(<ProductCard product={products[0]} />, { cart: { addItemToCart } });
    await userEvent.click(screen.getByRole('button', { name: 'Add to bag: Yoga Mat' }));
    expect(screen.getByRole('status').textContent).toContain('Could not add item');
  });
  it('replaces a failed photo and handles missing photos', () => {
    mount(<ProductCard product={products[0]} />);
    fireEvent.error(screen.getByRole('img'));
    expect(screen.getByText('Photo unavailable')).toBeTruthy();
    expect(screen.queryByRole('img')).toBeNull();
    cleanup();
    mount(<ProductCard product={products[2]} />);
    expect(screen.getByText('Photo unavailable')).toBeTruthy();
  });
  it('shows loading, failure and empty collection states', () => {
    const { unmount } = mount(<ProductGrid loading products={[]} />);
    expect(screen.getByLabelText('Loading products').getAttribute('aria-busy')).toBe('true');
    unmount();
    mount(<ProductGrid error products={[]} />);
    expect(screen.getByRole('status').textContent).toContain("couldn't load");
    cleanup();
    mount(<ProductGrid products={[]} />);
    expect(screen.getByText('Nothing here just yet.')).toBeTruthy();
    expect(screen.getByRole('link', { name: /Explore all essentials/ }).getAttribute('href')).toBe('/products/All');
  });
});

describe('shopping bag', () => {
  const filled = { cartItems: [{ productId: 'mat', productName: 'Yoga Mat', imageUrl: '/mat.jpg', price: 25, quantity: 2 }], subtotal: 50, noOfCartItems: 2 };
  it('stays out of the accessibility tree when closed', () => {
    mount(<Cart isCartOpen={false} onClose={vi.fn()} />);
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(document.body.style.overflow).toBe('');
  });
  it.each([null, signedIn])('offers an appropriate empty-bag link', user => {
    const onClose = vi.fn();
    const { unmount } = mount(<Cart isCartOpen onClose={onClose} />, { user });
    const dialog = screen.getByRole('dialog');
    const link = within(dialog).getByRole('link');
    expect(link.getAttribute('href')).toBe(user ? '/products/All' : '/auth/login');
    expect(document.body.style.overflow).toBe('hidden');
    fireEvent.click(link);
    expect(onClose).toHaveBeenCalledOnce();
    unmount();
    expect(document.body.style.overflow).toBe('');
  });
  it('updates quantities, removes items and navigates to checkout', async () => {
    const onClose = vi.fn();
    mount(<Cart isCartOpen onClose={onClose} />, { cart: { cart: filled } });
    await userEvent.click(screen.getByRole('button', { name: 'Increase Yoga Mat quantity' }));
    await userEvent.click(screen.getByRole('button', { name: 'Decrease Yoga Mat quantity' }));
    expect(cartValue.addItemToCart.mock.calls).toEqual([['mat', 1], ['mat', -1]]);
    await userEvent.click(screen.getByRole('button', { name: 'Remove Yoga Mat' }));
    expect(cartValue.removeItemFromCart).toHaveBeenCalledWith('mat');
    expect(screen.getByText('Rs. 50.00')).toBeTruthy();
    await userEvent.click(screen.getByRole('button', { name: /Continue to checkout/ }));
    expect(onClose).toHaveBeenCalledOnce();
    expect(screen.getByTestId('location').textContent).toBe('/order/checkout');
  });
  it.each([1, 20])('enforces the quantity boundary %i', quantity => {
    mount(<Cart isCartOpen onClose={vi.fn()} />, { cart: { cart: { ...filled, cartItems: [{ ...filled.cartItems[0], quantity }] } } });
    const name = quantity === 1 ? 'Decrease Yoga Mat quantity' : 'Increase Yoga Mat quantity';
    expect(screen.getByRole('button', { name }).disabled).toBe(true);
  });
  it('disables writes during processing and exposes API errors', () => {
    mount(<Cart isCartOpen onClose={vi.fn()} />, { cart: { cart: filled, isProcessingCart: true, cartError: true } });
    expect(screen.getByRole('alert').textContent).toContain("couldn't update");
    expect(screen.getByRole('button', { name: 'Remove Yoga Mat' }).disabled).toBe(true);
    expect(screen.getByRole('button', { name: /Continue to checkout/ }).disabled).toBe(true);
  });
  it('keeps keyboard focus inside the dialog in both directions', () => {
    mount(<Cart isCartOpen onClose={vi.fn()} />, { cart: { cart: filled } });
    const dialog = screen.getByRole('dialog');
    const first = within(dialog).getByRole('button', { name: 'Close shopping bag' });
    const last = within(dialog).getByRole('button', { name: /Continue to checkout/ });
    first.focus();
    fireEvent.keyDown(first, { key: 'Tab', shiftKey: true });
    expect(document.activeElement).toBe(last);
    fireEvent.keyDown(last, { key: 'Tab' });
    expect(document.activeElement).toBe(first);
    fireEvent.keyDown(first, { key: 'ArrowDown' });
    expect(document.activeElement).toBe(first);
  });
});

describe('header navigation', () => {
  it('encodes and trims search input while ignoring an empty query', async () => {
    mount(<Header />);
    await userEvent.click(screen.getByRole('button', { name: 'Search', exact: true }));
    expect(screen.getByTestId('location').textContent).toBe('/');
    await userEvent.type(screen.getByRole('searchbox'), '  yoga mat  ');
    await userEvent.click(screen.getByRole('button', { name: 'Search', exact: true }));
    expect(screen.getByTestId('location').textContent).toBe('/search/yoga%20mat');
  });
  it('opens and closes the mobile navigation with Escape', async () => {
    mount(<Header />, { user: null });
    await userEvent.click(screen.getByRole('button', { name: 'Open navigation' }));
    expect(screen.getByRole('button', { name: 'Close navigation' }).getAttribute('aria-expanded')).toBe('true');
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.getByRole('button', { name: 'Open navigation' }).getAttribute('aria-expanded')).toBe('false');
    expect(screen.getByRole('link', { name: 'Sign in', exact: true }).getAttribute('href')).toBe('/auth/login');
  });
  it('refreshes the bag, then restores button focus on close', async () => {
    mount(<Header />);
    const bag = screen.getByRole('button', { name: 'Open shopping bag, 0 items' });
    await userEvent.click(bag);
    expect(cartValue.getCartInformation).toHaveBeenCalledOnce();
    await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Close shopping bag' }));
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(document.activeElement).toBe(bag);
  });
  it('clears the session and bag when signing out', async () => {
    localStorage.setItem('user', JSON.stringify(signedIn));
    mount(<Header />);
    expect(screen.getByRole('link', { name: 'My account' }).getAttribute('href')).toBe('/my/account');
    await userEvent.click(screen.getAllByRole('button', { name: 'Sign out' })[0]);
    expect(localStorage.getItem('user')).toBeNull();
    expect(cartValue.clearCart).toHaveBeenCalledOnce();
    expect(authValue.toggleUser).toHaveBeenCalledOnce();
    expect(screen.getByTestId('location').textContent).toBe('/');
  });
});

describe('collection pages', () => {
  it('renders real catalog results and sorts their displayed order', async () => {
    mount(<Products />);
    await screen.findByRole('heading', { name: 'Yoga Mat' });
    expect(screen.getByText('3 essentials to explore')).toBeTruthy();
    await userEvent.selectOptions(screen.getByRole('combobox', { name: /Sort by/ }), 'low');
    expect(screen.getAllByRole('article').map(card => within(card).getByRole('heading').textContent)).toEqual(['Face Moisturizer', 'Pilates Ring', 'Yoga Mat']);
    await userEvent.selectOptions(screen.getByRole('combobox', { name: /Sort by/ }), 'high');
    expect(within(screen.getAllByRole('article')[0]).getByRole('heading').textContent).toBe('Yoga Mat');
  });
  it('uses the category in the URL even on a fresh visit', async () => {
    mount(<Routes><Route path="/products/:category" element={<Products />} /></Routes>, { path: '/products/Fitness%20Equipment' });
    await screen.findByRole('heading', { name: 'Yoga Mat' });
    expect(screen.queryByRole('heading', { name: 'Face Moisturizer' })).toBeNull();
    expect(screen.getByRole('link', { name: 'Fitness Equipment', exact: true }).getAttribute('aria-current')).toBe('page');
  });
  it('shows search results without collection filters', async () => {
    mount(<CatalogView searchTerm="moisturizer" />);
    await screen.findByRole('heading', { name: 'Face Moisturizer' });
    expect(screen.queryByRole('heading', { name: 'Yoga Mat' })).toBeNull();
    expect(screen.queryByRole('navigation', { name: 'Product collections' })).toBeNull();
    expect(screen.getByRole('heading', { level: 1 }).textContent).toContain('moisturizer');
  });
  it('normalizes category images and hides failed photos', async () => {
    expect(categoryImage(null)).toBeNull();
    expect(categoryImage('fitness.jpg')).toBe('/categories/fitness.jpg');
    expect(categoryImage('/local.jpg')).toBe('/local.jpg');
    expect(categoryImage('https://example.invalid/a.jpg')).toBe('https://example.invalid/a.jpg');
    axios.get.mockResolvedValue({ data: { success: true, response: [...categories, { id: 'test', categoryName: 'Demo Wellness test' }] } });
    mount(<Categories />);
    const link = await screen.findByRole('link', { name: /Fitness Equipment/ });
    expect(link.getAttribute('href')).toBe('/products/Fitness%20Equipment');
    expect(screen.queryByRole('link', { name: /Demo Wellness/ })).toBeNull();
    const image = link.querySelector('img');
    fireEvent.error(image);
    expect(image.style.visibility).toBe('hidden');
  });
  it('shows a useful fallback when collections fail', async () => {
    axios.get.mockRejectedValue(new Error('Unavailable'));
    mount(<Categories />);
    expect((await screen.findByRole('status')).textContent).toContain('Collections are taking a moment');
  });
  it('renders a homepage with real featured products and navigation', async () => {
    mount(<Home />, { user: null });
    await screen.findByRole('heading', { name: 'Yoga Mat' });
    expect(screen.getByRole('main').id).toBe('page-content');
    expect(screen.getByRole('heading', { name: 'Your kind of wellness.' })).toBeTruthy();
    expect(screen.getByRole('heading', { name: 'Everyday, made better.' })).toBeTruthy();
    expect(screen.getByRole('contentinfo')).toBeTruthy();
  });
  it('limits featured cards to four and prioritizes selected products', async () => {
    const extras = Array.from({ length: 5 }, (_, i) => ({ ...products[2], id: 'extra' + i, productName: 'Extra ' + i }));
    axios.get.mockImplementation(url => Promise.resolve({ data: { success: true, response: url.includes('category-service') ? categories : [...extras, products[0]] } }));
    mount(<Featured />);
    await screen.findByRole('heading', { name: 'Yoga Mat' });
    const cards = screen.getAllByRole('article');
    expect(cards).toHaveLength(4);
    expect(within(cards[0]).getByRole('heading').textContent).toBe('Yoga Mat');
  });
});

describe('cart provider contract', () => {
  const wrapper = ({ children }) => <CartProvider>{children}</CartProvider>;
  it('keeps an anonymous bag empty without an API request', async () => {
    const { result } = renderHook(() => React.useContext(CartContext), { wrapper });
    expect(result.current.cart.cartItems).toEqual([]);
    expect(axios.get).not.toHaveBeenCalled();
  });
  it('sends a correctly spaced Bearer header, refreshes and returns success', async () => {
    localStorage.setItem('user', JSON.stringify(signedIn));
    axios.get.mockResolvedValue({ data: { response: { ...emptyCart, cartId: 'demo-cart' } } });
    const { result } = renderHook(() => React.useContext(CartContext), { wrapper });
    await waitFor(() => expect(result.current.cart.cartId).toBe('demo-cart'));
    let success;
    await act(async () => { success = await result.current.addItemToCart('mat', 1); });
    expect(success).toBe(true);
    expect(axios.post).toHaveBeenCalledWith(expect.stringContaining('/cart/add'), { productId: 'mat', quantity: 1 }, { headers: { Authorization: 'Bearer unit-test-only' } });
    expect(axios.get).toHaveBeenCalledTimes(2);
    await act(async () => result.current.clearCart());
    expect(result.current.cart.cartItems).toEqual([]);
  });
  it('returns false when a write is rejected', async () => {
    localStorage.setItem('user', JSON.stringify(signedIn));
    axios.get.mockResolvedValue({ data: { response: emptyCart } });
    axios.post.mockRejectedValue(new Error('Unavailable'));
    const { result } = renderHook(() => React.useContext(CartContext), { wrapper });
    await waitFor(() => expect(result.current.isProcessingCart).toBe(false));
    let success;
    await act(async () => { success = await result.current.addItemToCart('mat', 1); });
    expect(success).toBe(false);
  });
});

describe('order submission', () => {
  const wrapper = ({ children }) => <MemoryRouter>{children}</MemoryRouter>;
  const address = { fname: 'Demo', lname: 'Shopper', address1: 'Test street', address2: '', city: 'Demo City', phone: '0000000000' };
  it('passes the cart and authenticated address to the API', async () => {
    localStorage.setItem('user', JSON.stringify(signedIn));
    const { result } = renderHook(() => OrderService(), { wrapper });
    await waitFor(() => expect(result.current.isLoading).toBe(false));
    await act(async () => result.current.placeOrder(address, 'cart-1'));
    expect(axios.post).toHaveBeenCalledWith(expect.stringContaining('/order/create'), {
      firstName: 'Demo', lastName: 'Shopper', addressLine1: 'Test street', addressLine2: '',
      city: 'Demo City', phoneNo: '0000000000', cartId: 'cart-1',
    }, { headers: { Authorization: 'Bearer unit-test-only' } });
    expect(result.current.orderError).toBeNull();
    expect(result.current.isLoading).toBe(false);
  });
  it.each(['network', 'envelope'])('rejects a failed order (%s) and allows retry', async failure => {
    axios.post.mockImplementationOnce(() => failure === 'network' ? Promise.reject(new Error('Unavailable')) : Promise.resolve({ data: { success: false } }));
    const { result } = renderHook(() => OrderService(), { wrapper });
    await waitFor(() => expect(result.current.isLoading).toBe(false));
    await act(async () => { await expect(result.current.placeOrder(address, 'cart-1')).rejects.toThrow('Order was not placed'); });
    expect(result.current.orderError).toContain('Your bag has been kept');
    expect(result.current.isLoading).toBe(false);
    await act(async () => result.current.placeOrder(address, 'cart-1'));
    expect(result.current.orderError).toBeNull();
  });
  it('disables checkout for an empty bag', async () => {
    mount(<CheckoutForm />);
    await waitFor(() => expect(screen.getByRole('button', { name: 'Place Order' }).disabled).toBe(true));
  });
  it.each([true, false])('clears the bag only after a successful checkout (%s)', async success => {
    axios.post.mockResolvedValue({ data: { success } });
    mount(<CheckoutForm />, { cart: { cart: {
      ...emptyCart, cartId: 'cart-1', subtotal: 25,
      cartItems: [{ productId: 'mat', productName: 'Yoga Mat', price: 25, quantity: 1, amount: 25, imageUrl: '/mat.jpg' }],
    } } });
    await waitFor(() => expect(screen.getByRole('button', { name: 'Place Order' }).disabled).toBe(false));
    for (const [label, value] of [['First Name', 'Demo'], ['Last Name', 'Shopper'], ['Address Line 1', 'Test street'], ['City', 'Demo City'], ['Phone Number', '0000000000']]) {
      await userEvent.type(screen.getByLabelText(label, { exact: true }), value);
    }
    await userEvent.click(screen.getByRole('button', { name: 'Place Order' }));
    await waitFor(() => expect(axios.post).toHaveBeenCalledOnce());
    if (success) {
      await waitFor(() => expect(screen.getByTestId('location').textContent).toBe('/order/success'));
      expect(cartValue.clearCart).toHaveBeenCalledOnce();
    } else {
      await screen.findByText(/Your order could not be placed/);
      expect(cartValue.clearCart).not.toHaveBeenCalled();
      expect(screen.getByRole('button', { name: 'Place Order' }).disabled).toBe(false);
      expect(screen.getByTestId('location').textContent).toBe('/');
    }
  });
});

describe('application routing', () => {
  it('renders the homepage through the real providers and resets scroll', async () => {
    window.history.replaceState({}, '', '/');
    const scroll = vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
    render(<App />);
    await screen.findByRole('heading', { name: 'Yoga Mat' });
    expect(scroll).toHaveBeenCalledWith(0, 0);
    expect(screen.getByRole('link', { name: 'Skip to content' }).getAttribute('href')).toBe('#page-content');
  });
  it('renders bookmarked search results through the actual route', async () => {
    window.history.replaceState({}, '', '/search/yoga');
    vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
    render(<App />);
    await screen.findByRole('heading', { name: 'Yoga Mat' });
    expect(screen.queryByRole('heading', { name: 'Face Moisturizer' })).toBeNull();
    expect(screen.getByRole('heading', { level: 1 }).textContent).toContain('yoga');
  });
});
