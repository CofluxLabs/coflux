import coflux as cf
import csv
from faker import Faker
from pathlib import Path
import random
import pandas as pd
import matplotlib.pyplot as plt

fake = Faker()


def _write_csv_asset(filename, fieldnames, data):
    file_path = Path.cwd().joinpath(filename)
    with open(file_path, mode="w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(data)
    return cf.persist_asset(file_path)


@cf.task()
def generate_customers(count: int):
    return _write_csv_asset(
        "customers.csv",
        ["id", "name", "address", "email"],
        (
            {
                "id": fake.uuid4(),
                "name": fake.name(),
                "address": fake.address(),
                "email": fake.email(),
            }
            for _ in range(count)
        ),
    )


@cf.task()
def generate_categories(count: int):
    return _write_csv_asset(
        "categories.csv",
        ["id", "name"],
        ({"id": fake.uuid4(), "name": fake.word()} for _ in range(count)),
    )


def _load_ids(asset):
    with open(cf.restore_asset(asset), newline="") as file:
        return {row["id"] for row in csv.DictReader(file)}


@cf.task(wait={"categories_"})
def generate_products(count: int, categories_: cf.Execution[cf.Asset]):
    category_ids = list(_load_ids(categories_.result()))
    return _write_csv_asset(
        "products.csv",
        ["id", "name", "category_id", "unit_price"],
        (
            {
                "id": fake.uuid4(),
                "name": fake.word(),
                "category_id": random.choice(category_ids),
                "unit_price": round(random.uniform(5.0, 100.0), 2),
            }
            for _ in range(count)
        ),
    )


@cf.task(wait={"products_", "customers_"})
def generate_sales(
    count: int, products_: cf.Execution[cf.Asset], customers_: cf.Execution[cf.Asset]
):
    product_ids = list(_load_ids(products_.result()))
    customer_ids = list(_load_ids(customers_.result()))
    return _write_csv_asset(
        "transactions.csv",
        [
            "id",
            "product_id",
            "customer_id",
            "timestamp",
            "quantity_sold",
            "sale_amount",
        ],
        (
            {
                "id": fake.uuid4(),
                "product_id": random.choice(product_ids),
                "customer_id": random.choice(customer_ids),
                "timestamp": fake.date_between(start_date="-365d", end_date="today"),
                "quantity_sold": random.randint(1, 50),
                "sale_amount": round(random.uniform(10.0, 200.0), 2),
            }
            for _ in range(count)
        ),
    )


@cf.task(memo=True)
def load_dataset():
    customers_ = generate_customers.submit(2000)
    categories_ = generate_categories.submit(25)
    products_ = generate_products.submit(500, categories_)
    sales_ = generate_sales.submit(1000, products_, customers_)
    return {
        "customers": customers_,
        "categories": categories_,
        "products": products_,
        "sales": sales_,
    }


def _load_csv(execution):
    return pd.read_csv(cf.restore_asset(execution.result()))


@cf.task(wait={"dataset_"})
def generate_sales_summary(dataset_):
    dataset = dataset_.result()
    sales_data = _load_csv(dataset["sales"])
    product_data = _load_csv(dataset["products"])

    sales_summary = (
        sales_data.groupby("product_id")
        .agg({"quantity_sold": "sum", "sale_amount": "sum"})
        .reset_index()
    )

    sales_summary = pd.merge(
        sales_summary,
        product_data[["id", "name", "category_id"]],
        left_on="product_id",
        right_on="id",
        how="left",
    )

    sales_summary.rename(
        columns={
            "quantity_sold": "total_quantity_sold",
            "sale_amount": "total_sale_amount",
            "name": "product_name",
        },
        inplace=True,
    )

    return sales_summary


@cf.task(wait=True)
def write_sales_summary(sales_summary_):
    sales_summary = sales_summary_.result()
    return _write_csv_asset(
        "sales_summary.csv",
        list(sales_summary.columns),
        (row._asdict() for row in sales_summary.itertuples(index=False)),
    )


@cf.task(wait=True)
def render_chart(sales_summary_, dataset_):
    sales_summary = sales_summary_.result()
    categories_asset = dataset_.result()["categories"].result()

    with open(cf.restore_asset(categories_asset), newline="") as file:
        categories_by_id = {row["id"]: row["name"] for row in csv.DictReader(file)}

    category_sales = (
        sales_summary.groupby("category_id")["total_quantity_sold"]
        .sum()
        .sort_values(ascending=False)
    )

    plt.figure(figsize=(10, 6))
    plt.bar(category_sales.index.map(categories_by_id), category_sales, color="skyblue")
    plt.title("Total Quantity Sold per Product Category")
    plt.xlabel("Product Category")
    plt.ylabel("Total Quantity Sold")
    plt.xticks(rotation=45, ha="right")
    plt.tight_layout()

    path = Path.cwd().joinpath("sales_summary_chart.png")
    plt.savefig(path)

    return cf.persist_asset(path)


@cf.workflow()
def workflow():
    dataset = load_dataset.submit()
    sales_summary = generate_sales_summary.submit(dataset)
    write_sales_summary.submit(sales_summary)
    render_chart.submit(sales_summary, dataset)
