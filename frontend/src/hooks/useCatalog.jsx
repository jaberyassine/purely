import { useEffect, useState } from 'react';
import axios from 'axios';
import API_BASE_URL from '../api-service/apiConfig';

export default function useCatalog() {
  const [state, setState] = useState({ products: [], categories: [], loading: true, error: false });
  useEffect(() => {
    const controller = new AbortController();
    Promise.all([
      axios.get(API_BASE_URL + '/product-service/product/get/all', { signal: controller.signal }),
      axios.get(API_BASE_URL + '/category-service/category/get/all', { signal: controller.signal }),
    ]).then(([products, categories]) => {
      if (!products.data.success || !categories.data.success) throw new Error('Catalog unavailable');
      setState({ products: products.data.response || [], categories: categories.data.response || [], loading: false, error: false });
    }).catch(error => {
      if (!controller.signal.aborted) setState({ products: [], categories: [], loading: false, error: true });
    });
    return () => controller.abort();
  }, []);
  return state;
}