import { api, ensureAuth, formatMoney } from './api.js';

ensureAuth();

const table = document.getElementById('categories-table');
const form = document.getElementById('category-form');
const resetBtn = document.getElementById('category-reset');
let editingId = null;

async function load() {
  const list = await api('/categories/');
  table.innerHTML = list.map((c) => `
    <tr>
      <td>${c.id}</td>
      <td>${c.emoji} ${c.name}</td>
      <td>${c.description || ''}</td>
      <td>${formatMoney(c.price)}</td>
      <td>${c.stock}</td>
      <td>${c.is_active ? 'Bật' : 'Tắt'}</td>
      <td>
        <button onclick='window.editCategory(${JSON.stringify(c)})'>Sửa</button>
        <button class='danger' onclick='window.deleteCategory(${c.id})'>Xóa</button>
      </td>
    </tr>
  `).join('');
}

window.editCategory = (c) => {
  editingId = c.id;
  form.name.value = c.name;
  form.description.value = c.description || '';
  form.price.value = c.price;
  form.emoji.value = c.emoji;
  form.is_active.value = c.is_active;
};

window.deleteCategory = async (id) => {
  if (!confirm('Xóa danh mục?')) return;
  try {
    await api(`/categories/${id}`, { method: 'DELETE' });
    await load();
  } catch (e) {
    alert(e.message);
  }
};

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const payload = {
    name: form.name.value,
    description: form.description.value,
    price: Number(form.price.value),
    emoji: form.emoji.value,
    is_active: Number(form.is_active.value),
  };

  try {
    if (editingId) {
      await api(`/categories/${editingId}`, {
        method: 'PUT',
        body: JSON.stringify(payload),
      });
    } else {
      await api('/categories/', {
        method: 'POST',
        body: JSON.stringify(payload),
      });
    }

    editingId = null;
    form.reset();
    await load();
  } catch (err) {
    alert(err.message);
  }
});

resetBtn.addEventListener('click', () => {
  editingId = null;
  form.reset();
});

load();
