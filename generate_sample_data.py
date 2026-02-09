"""
Generate sample e-commerce data for the Azure Data Engineering Pipeline project.
Creates customers, products, and orders datasets.
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random
import os

# Set random seed for reproducibility
np.random.seed(42)
random.seed(42)

# Create data directory if it doesn't exist
os.makedirs('data', exist_ok=True)

def generate_customers(num_customers=1000):
    """Generate customer data"""
    
    first_names = ['John', 'Jane', 'Michael', 'Emily', 'David', 'Sarah', 'James', 'Emma', 
                   'Robert', 'Olivia', 'William', 'Ava', 'Richard', 'Sophia', 'Joseph']
    last_names = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 
                  'Davis', 'Rodriguez', 'Martinez', 'Wilson', 'Anderson', 'Taylor']
    cities = ['New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix', 'Philadelphia', 
              'San Antonio', 'San Diego', 'Dallas', 'San Jose']
    states = ['NY', 'CA', 'IL', 'TX', 'AZ', 'PA', 'TX', 'CA', 'TX', 'CA']
    
    customers = []
    
    for i in range(1, num_customers + 1):
        city_idx = random.randint(0, len(cities) - 1)
        customer = {
            'customer_id': i,
            'first_name': random.choice(first_names),
            'last_name': random.choice(last_names),
            'email': f'customer{i}@email.com',
            'city': cities[city_idx],
            'state': states[city_idx],
            'zipcode': f'{random.randint(10000, 99999)}',
            'registration_date': (datetime.now() - timedelta(days=random.randint(1, 730))).strftime('%Y-%m-%d'),
            'customer_segment': random.choice(['Premium', 'Standard', 'Basic'])
        }
        customers.append(customer)
    
    df = pd.DataFrame(customers)
    df.to_csv('data/customers.csv', index=False)
    print(f"✓ Generated {num_customers} customers")
    return df

def generate_products(num_products=200):
    """Generate product data"""
    
    categories = ['Electronics', 'Clothing', 'Home & Garden', 'Books', 'Sports', 'Toys']
    
    product_names = {
        'Electronics': ['Laptop', 'Smartphone', 'Headphones', 'Tablet', 'Smartwatch', 'Camera'],
        'Clothing': ['T-Shirt', 'Jeans', 'Dress', 'Jacket', 'Shoes', 'Hat'],
        'Home & Garden': ['Lamp', 'Chair', 'Table', 'Vase', 'Curtains', 'Rug'],
        'Books': ['Fiction Novel', 'Cookbook', 'Biography', 'Science Book', 'History Book'],
        'Sports': ['Yoga Mat', 'Dumbbells', 'Running Shoes', 'Basketball', 'Tennis Racket'],
        'Toys': ['Action Figure', 'Board Game', 'Puzzle', 'Doll', 'Building Blocks']
    }
    
    products = []
    
    for i in range(1, num_products + 1):
        category = random.choice(categories)
        product = {
            'product_id': i,
            'product_name': f"{random.choice(product_names[category])} - Model {i}",
            'category': category,
            'price': round(random.uniform(10, 1000), 2),
            'cost': round(random.uniform(5, 500), 2),
            'supplier_id': random.randint(1, 20),
            'stock_quantity': random.randint(0, 500),
            'rating': round(random.uniform(3.0, 5.0), 1)
        }
        products.append(product)
    
    df = pd.DataFrame(products)
    df.to_csv('data/products.csv', index=False)
    print(f"✓ Generated {num_products} products")
    return df

def generate_orders(customers_df, products_df, num_orders=5000):
    """Generate order data"""
    
    orders = []
    order_items = []
    
    start_date = datetime.now() - timedelta(days=365)
    
    for i in range(1, num_orders + 1):
        customer_id = random.choice(customers_df['customer_id'].tolist())
        order_date = start_date + timedelta(days=random.randint(0, 365))
        
        # Number of items in order (1-5)
        num_items = random.randint(1, 5)
        order_total = 0
        
        selected_products = random.sample(products_df['product_id'].tolist(), num_items)
        
        for product_id in selected_products:
            product_price = products_df[products_df['product_id'] == product_id]['price'].values[0]
            quantity = random.randint(1, 3)
            item_total = product_price * quantity
            order_total += item_total
            
            order_items.append({
                'order_id': i,
                'product_id': product_id,
                'quantity': quantity,
                'unit_price': product_price,
                'total_price': round(item_total, 2)
            })
        
        # Apply discount randomly
        discount = random.choice([0, 0, 0, 0.05, 0.10, 0.15])
        final_total = order_total * (1 - discount)
        
        order = {
            'order_id': i,
            'customer_id': customer_id,
            'order_date': order_date.strftime('%Y-%m-%d'),
            'order_time': f"{random.randint(0, 23):02d}:{random.randint(0, 59):02d}:{random.randint(0, 59):02d}",
            'subtotal': round(order_total, 2),
            'discount_amount': round(order_total * discount, 2),
            'tax': round(final_total * 0.08, 2),
            'total_amount': round(final_total * 1.08, 2),
            'payment_method': random.choice(['Credit Card', 'Debit Card', 'PayPal', 'Cash']),
            'status': random.choice(['Completed', 'Completed', 'Completed', 'Pending', 'Cancelled']),
            'shipping_method': random.choice(['Standard', 'Express', 'Next Day'])
        }
        orders.append(order)
    
    orders_df = pd.DataFrame(orders)
    orders_df.to_csv('data/orders.csv', index=False)
    print(f"✓ Generated {num_orders} orders")
    
    order_items_df = pd.DataFrame(order_items)
    order_items_df.to_csv('data/order_items.csv', index=False)
    print(f"✓ Generated {len(order_items)} order items")
    
    return orders_df, order_items_df

def generate_all_data():
    """Generate all datasets"""
    print("\n" + "="*50)
    print("Generating Sample E-commerce Data")
    print("="*50 + "\n")
    
    customers_df = generate_customers(1000)
    products_df = generate_products(200)
    orders_df, order_items_df = generate_orders(customers_df, products_df, 5000)
    
    print("\n" + "="*50)
    print("Data Generation Complete!")
    print("="*50)
    print("\nSummary:")
    print(f"  - Customers: {len(customers_df)} records")
    print(f"  - Products: {len(products_df)} records")
    print(f"  - Orders: {len(orders_df)} records")
    print(f"  - Order Items: {len(order_items_df)} records")
    print(f"\nFiles saved to: ./data/")
    print("\nNext steps:")
    print("  1. Review the generated CSV files in the data/ folder")
    print("  2. Deploy Azure infrastructure using infrastructure/deploy.sh")
    print("  3. Upload data to Azure Data Lake Storage Gen2")
    
    return customers_df, products_df, orders_df, order_items_df

if __name__ == "__main__":
    generate_all_data()
