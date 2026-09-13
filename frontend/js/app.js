'use strict';
/* ═══════════════════════════════════════════════════
   CloudCart — Frontend JavaScript
   ═══════════════════════════════════════════════════ */

const API = '/api';
const CART_KEY  = 'cloudcart_cart';
const TOKEN_KEY = 'cloudcart_token';

/* ─────────────────────────────────────────────────
   TOAST
───────────────────────────────────────────────── */
function showToast(message, type = 'info', duration = 3500) {
  let container = document.getElementById('toast-container');
  if (!container) {
    container = document.createElement('div');
    container.id = 'toast-container';
    document.body.appendChild(container);
  }

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  container.appendChild(toast);

  requestAnimationFrame(() => {
    requestAnimationFrame(() => toast.classList.add('show'));
  });

  setTimeout(() => {
    toast.classList.remove('show');
    setTimeout(() => toast.remove(), 300);
  }, duration);
}

/* ─────────────────────────────────────────────────
   CART UTILITIES
───────────────────────────────────────────────── */
function getCart() {
  try { return JSON.parse(localStorage.getItem(CART_KEY) || '[]'); }
  catch { return []; }
}

function saveCart(cart) {
  localStorage.setItem(CART_KEY, JSON.stringify(cart));
  updateCartBadge();
}

function cartTotal() {
  return getCart().reduce((sum, item) => sum + Number(item.price) * item.quantity, 0);
}

function updateCartBadge() {
  const count = getCart().reduce((n, i) => n + i.quantity, 0);
  document.querySelectorAll('.cart-badge').forEach(el => {
    el.setAttribute('data-count', count);
    el.textContent = count;
    el.classList.remove('bump');
    void el.offsetWidth;                          // force reflow for animation
    if (count > 0) el.classList.add('bump');
  });
}

function addToCart(product) {
  const cart = getCart();
  const existing = cart.find(x => x.id === product.id);
  if (existing) {
    existing.quantity += 1;
  } else {
    cart.push({ ...product, quantity: 1 });
  }
  saveCart(cart);
  showToast(`✓ "${escapeHtml(product.name)}" added to cart`, 'success');
}

/* ─────────────────────────────────────────────────
   AUTH UTILITIES
───────────────────────────────────────────────── */
function getToken()    { return localStorage.getItem(TOKEN_KEY); }
function isLoggedIn()  { return Boolean(getToken()); }

function logout() {
  localStorage.removeItem(TOKEN_KEY);
  updateNavAuth();
  showToast('Logged out', 'info');
  setTimeout(() => { window.location.href = '/'; }, 600);
}

function updateNavAuth() {
  const loggedIn = isLoggedIn();
  document.querySelectorAll('[data-auth="logged-in"]').forEach(el => {
    el.style.display = loggedIn ? '' : 'none';
  });
  document.querySelectorAll('[data-auth="logged-out"]').forEach(el => {
    el.style.display = loggedIn ? 'none' : '';
  });
}

/* ─────────────────────────────────────────────────
   NAV ACTIVE STATE
───────────────────────────────────────────────── */
function highlightActiveNav() {
  const path = window.location.pathname.replace(/\/$/, '') || '/';
  document.querySelectorAll('.nav-links a').forEach(a => {
    const href = a.getAttribute('href');
    const isActive = href === path || (href !== '/' && path.startsWith(href));
    a.classList.toggle('active', isActive);
  });
}

/* ─────────────────────────────────────────────────
   API FETCH WRAPPER
───────────────────────────────────────────────── */
async function apiFetch(path, options = {}) {
  const token = getToken();
  const headers = { 'Content-Type': 'application/json', ...options.headers };
  if (token) headers['Authorization'] = `Bearer ${token}`;

  const res = await fetch(API + path, { ...options, headers });
  const data = await res.json().catch(() => null);

  if (!res.ok) {
    const detail = data?.detail || `Request failed (${res.status})`;
    throw Object.assign(new Error(detail), { status: res.status, data });
  }
  return data;
}

/* ─────────────────────────────────────────────────
   PRODUCTS PAGE
───────────────────────────────────────────────── */
let _currentPage = 1;
let _currentSearch = '';

async function loadProducts(page = 1, search = '') {
  const target = document.getElementById('products');
  if (!target) return;

  _currentPage   = page;
  _currentSearch = search;

  target.innerHTML = `
    <div class="loading-wrap" style="grid-column:1/-1">
      <div class="spinner"></div>
      <p>Loading products…</p>
    </div>`;

  try {
    const params = new URLSearchParams({ page, page_size: 8 });
    if (search) params.set('search', search);

    const data = await apiFetch(`/products?${params}`);
    const products = data.items ?? [];
    const { total, pages } = data;

    if (!products.length) {
      target.innerHTML = `<p style="grid-column:1/-1;color:var(--text-muted);padding:40px 0">
        No products found${search ? ` for "<strong>${escapeHtml(search)}</strong>"` : ''}.
      </p>`;
    } else {
      target.innerHTML = products.map(p => {
        const stockClass = p.stock === 0 ? 'out' : p.stock < 5 ? 'low' : '';
        const stockText  = p.stock === 0 ? 'Out of stock' : p.stock < 5 ? `Only ${p.stock} left!` : `In stock (${p.stock})`;
        return `
          <article class="card">
            <h3>${escapeHtml(p.name)}</h3>
            <p class="desc">${escapeHtml(p.description || '')}</p>
            <p class="price">₹${Number(p.price).toFixed(2)}</p>
            <p class="stock-label ${stockClass}">${stockText}</p>
            <button
              class="btn btn-primary btn-sm"
              ${p.stock === 0 ? 'disabled' : ''}
              onclick='addToCart(${JSON.stringify(p)})'>
              ${p.stock === 0 ? 'Out of Stock' : 'Add to Cart'}
            </button>
          </article>`;
      }).join('');
    }

    renderPagination(page, pages, total);

  } catch (err) {
    target.innerHTML = `<p style="grid-column:1/-1;color:var(--danger)">
      ⚠ Could not load products — ${escapeHtml(err.message)}
    </p>`;
  }
}

function renderPagination(page, pages, total) {
  const el = document.getElementById('pagination');
  if (!el) return;
  if (pages <= 1) { el.innerHTML = ''; return; }

  el.innerHTML = `
    <button class="btn btn-ghost btn-sm" ${page <= 1 ? 'disabled' : ''}
      onclick="loadProducts(${page - 1}, '${escapeHtml(_currentSearch)}')">← Prev</button>
    <span class="pagination-info">Page ${page} of ${pages} (${total} items)</span>
    <button class="btn btn-ghost btn-sm" ${page >= pages ? 'disabled' : ''}
      onclick="loadProducts(${page + 1}, '${escapeHtml(_currentSearch)}')">Next →</button>
  `;
}

function initSearch() {
  const form = document.getElementById('search-form');
  if (!form) return;
  form.addEventListener('submit', e => {
    e.preventDefault();
    const q = document.getElementById('search-input')?.value.trim() ?? '';
    loadProducts(1, q);
  });
}

/* ─────────────────────────────────────────────────
   CART PAGE
───────────────────────────────────────────────── */
function renderCart() {
  const target = document.getElementById('cart');
  if (!target) return;

  const cart = getCart();

  if (!cart.length) {
    target.innerHTML = `
      <div class="cart-empty">
        <p>Your cart is empty.</p>
        <a href="/products.html" class="btn btn-primary">Browse Products</a>
      </div>`;
    const summary = document.getElementById('cart-summary');
    if (summary) summary.style.display = 'none';
    return;
  }

  target.innerHTML = cart.map((item, idx) => `
    <div class="cart-item">
      <div class="cart-item-info">
        <h3>${escapeHtml(item.name)}</h3>
        <p>₹${Number(item.price).toFixed(2)} each</p>
      </div>
      <div class="cart-item-qty">
        <button class="qty-btn" onclick="changeQty(${idx}, -1)">−</button>
        <span>${item.quantity}</span>
        <button class="qty-btn" onclick="changeQty(${idx}, 1)">+</button>
      </div>
      <div class="cart-item-price">₹${(Number(item.price) * item.quantity).toFixed(2)}</div>
      <button class="btn btn-danger btn-sm" onclick="removeFromCart(${idx})">✕</button>
    </div>
  `).join('');

  const totalEl = document.getElementById('cart-total-amount');
  if (totalEl) totalEl.textContent = `₹${cartTotal().toFixed(2)}`;

  const summary = document.getElementById('cart-summary');
  if (summary) summary.style.display = '';
}

function changeQty(idx, delta) {
  const cart = getCart();
  if (!cart[idx]) return;
  cart[idx].quantity += delta;
  if (cart[idx].quantity <= 0) cart.splice(idx, 1);
  saveCart(cart);
  renderCart();
}

function removeFromCart(idx) {
  const cart = getCart();
  const name = cart[idx]?.name;
  cart.splice(idx, 1);
  saveCart(cart);
  renderCart();
  if (name) showToast(`Removed "${escapeHtml(name)}" from cart`, 'info');
}

async function checkout() {
  if (!isLoggedIn()) {
    showToast('Please login before checkout', 'error');
    setTimeout(() => { window.location.href = '/login.html'; }, 1000);
    return;
  }

  const cart = getCart();
  if (!cart.length) { showToast('Your cart is empty', 'error'); return; }

  const checkoutBtn = document.getElementById('checkout-btn');
  if (checkoutBtn) { checkoutBtn.disabled = true; checkoutBtn.textContent = 'Placing order…'; }

  try {
    const items = cart.map(i => ({ product_id: i.id, quantity: i.quantity }));
    const order = await apiFetch('/orders', {
      method: 'POST',
      body: JSON.stringify({ items }),
    });
    saveCart([]);
    renderCart();
    showToast(`✓ Order #${order.id} placed — total ₹${Number(order.total_amount).toFixed(2)}`, 'success', 5000);
  } catch (err) {
    showToast(`Checkout failed: ${err.message}`, 'error');
  } finally {
    if (checkoutBtn) { checkoutBtn.disabled = false; checkoutBtn.textContent = 'Place Order'; }
  }
}

/* ─────────────────────────────────────────────────
   ORDERS PAGE
───────────────────────────────────────────────── */
async function loadOrders() {
  const target = document.getElementById('orders');
  if (!target) return;

  if (!isLoggedIn()) {
    target.innerHTML = `<p>Please <a href="/login.html">login</a> to view your orders.</p>`;
    return;
  }

  target.innerHTML = `<div class="loading-wrap"><div class="spinner"></div><p>Loading orders…</p></div>`;

  try {
    const orders = await apiFetch('/orders');

    if (!orders.length) {
      target.innerHTML = `
        <div class="cart-empty">
          <p>No orders yet.</p>
          <a href="/products.html" class="btn btn-primary">Start Shopping</a>
        </div>`;
      return;
    }

    target.innerHTML = orders.map(o => `
      <div class="order-card">
        <div class="order-header">
          <span class="order-id">Order #${o.id}</span>
          <span class="order-date">${new Date(o.created_at).toLocaleDateString('en-IN', { day:'numeric', month:'short', year:'numeric' })}</span>
          <span class="status-badge status-${o.status.toLowerCase()}">${o.status}</span>
        </div>
        <div class="order-items">
          ${(o.items || []).map(i => `
            <div style="display:flex;justify-content:space-between;font-size:.88rem;padding:4px 0;border-bottom:1px solid var(--border)">
              <span>${escapeHtml(i.product_name)} × ${i.quantity}</span>
              <span>₹${(Number(i.unit_price) * i.quantity).toFixed(2)}</span>
            </div>`).join('')}
        </div>
        <div style="display:flex;justify-content:flex-end;margin-top:12px;font-weight:700">
          Total: ₹${Number(o.total_amount).toFixed(2)}
        </div>
      </div>`).join('');

  } catch (err) {
    target.innerHTML = `<p style="color:var(--danger)">⚠ Could not load orders — ${escapeHtml(err.message)}</p>`;
  }
}

/* ─────────────────────────────────────────────────
   LOGIN PAGE
───────────────────────────────────────────────── */
async function handleLogin(event) {
  event.preventDefault();
  const email    = document.getElementById('email')?.value.trim();
  const password = document.getElementById('password')?.value;
  const msgEl    = document.getElementById('form-message');
  const btn      = event.submitter;

  if (btn) { btn.disabled = true; btn.textContent = 'Logging in…'; }
  if (msgEl) { msgEl.className = 'form-message'; msgEl.textContent = ''; }

  try {
    const data = await apiFetch('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    });
    localStorage.setItem(TOKEN_KEY, data.access_token);
    showToast('✓ Login successful', 'success');
    setTimeout(() => { window.location.href = '/products.html'; }, 700);
  } catch (err) {
    if (msgEl) { msgEl.className = 'form-message error'; msgEl.textContent = err.message; }
  } finally {
    if (btn) { btn.disabled = false; btn.textContent = 'Login'; }
  }
}

/* ─────────────────────────────────────────────────
   REGISTER PAGE
───────────────────────────────────────────────── */
async function handleRegister(event) {
  event.preventDefault();
  const email    = document.getElementById('email')?.value.trim();
  const password = document.getElementById('password')?.value;
  const confirm  = document.getElementById('confirm-password')?.value;
  const msgEl    = document.getElementById('form-message');
  const btn      = event.submitter;

  if (msgEl) { msgEl.className = 'form-message'; msgEl.textContent = ''; }

  if (password !== confirm) {
    if (msgEl) { msgEl.className = 'form-message error'; msgEl.textContent = 'Passwords do not match.'; }
    return;
  }

  if (btn) { btn.disabled = true; btn.textContent = 'Creating account…'; }

  try {
    await apiFetch('/auth/register', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    });
    if (msgEl) {
      msgEl.className = 'form-message success';
      msgEl.textContent = '✓ Account created! Redirecting to login…';
    }
    setTimeout(() => { window.location.href = '/login.html'; }, 1500);
  } catch (err) {
    if (msgEl) { msgEl.className = 'form-message error'; msgEl.textContent = err.message; }
  } finally {
    if (btn) { btn.disabled = false; btn.textContent = 'Create Account'; }
  }
}

/* ─────────────────────────────────────────────────
   UTILS
───────────────────────────────────────────────── */
function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#039;',
  }[c]));
}

/* ─────────────────────────────────────────────────
   INIT
───────────────────────────────────────────────── */
document.addEventListener('DOMContentLoaded', () => {
  updateCartBadge();
  updateNavAuth();
  highlightActiveNav();

  // Attach logout button
  document.querySelectorAll('[data-action="logout"]').forEach(el => {
    el.addEventListener('click', e => { e.preventDefault(); logout(); });
  });

  // Page-specific init
  loadProducts();
  renderCart();
  loadOrders();
  initSearch();

  const loginForm    = document.getElementById('login-form');
  const registerForm = document.getElementById('register-form');
  if (loginForm)    loginForm.addEventListener('submit', handleLogin);
  if (registerForm) registerForm.addEventListener('submit', handleRegister);
});
