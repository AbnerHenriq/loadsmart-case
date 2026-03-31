# Analytics Engineer Challenge
## Data Enablement Team — Loadsmart

---

Hello! Thank you for your interest in Loadsmart. We appreciate your interest in our company and are excited that you chose to move forward to this stage! We hope you find the challenge stimulating and fun, and we look forward to discussing your results with you!

The challenge will help us better understand your technical skills. We will use your results together with other dimensions when considering your fit for the role. This is not the only factor we consider for your application. If, for any reason, you cannot complete the entire challenge, any progress you make will be taken into account in the broader picture. Please advance as far as you can and we will cover Q&A in the technical interview.

You have up to seven days to complete the challenge and send it back to us. **Be sure you have confirmed the due date with the representative who sent you the challenge.**

After completing the challenge, email the representative who sent it a link to your GitHub repository, including the `README.md` with the steps needed to test your proposed solution. Please use the email subject **"YOUR FULL NAME - Analytics Engineer Challenge"**.

Good luck and have fun!

---

We attached a dataset for you to work with. **Please find the CSV file attached to the email. Here is what we ask you to do:**

---

## 1. Dimensional modeling, SQL, and dbt skills

**a. Ingest the data and build a dimensional data model (Star Schema):** use **dbt (data build tool)** and a compatible database to demonstrate your data model. This will ensure data analysis is available via SQL.

---

## 2. Python skills

**a. Python functions:** please create one or more of the following Python functions in a Jupyter Notebook:

**i. Create a Python function to split the lane column:** create a function that takes a lane value and splits it into 4 new columns: `pickup_city`, `pickup_state`, `delivery_city`, and `delivery_state`.

**ii. Create a Python function to email a CSV file:** create a function to send a CSV file to an email address. The Python function should take a CSV file path, email subject, and email body.

**iii. Create a Python function to send a CSV file via sFTP:** create a function to send a CSV file to an sFTP server. The Python function should take a CSV file path and the destination file path.

**b. Export a CSV file using a Python script:** please use the same Jupyter Notebook created above to write a Python script that reads your dimensional model and creates an export to a CSV file. This file should contain the list of `loadsmart_ids` that were delivered in the last month available in the raw CSV data we sent you. Below is the list of columns that must be in the exported CSV file:

| # | Column |
|---|---|
| i | loadsmart_id |
| ii | shipper_name |
| iii | delivery_date |
| iv | pickup_city |
| v | pickup_state |
| vi | delivery_city |
| vii | delivery_state |
| viii | book_price |
| ix | carrier_name |

---

If you are able to create reports, please try to fulfill this last requirement:

## 3. Data visualization

**a. Create a report using the modeled data:** provide a visual analysis as a proof of concept of how your data model works and how we can use it. You may use Power BI Desktop or Superset.

---

## Repository deliverables

1. The dbt project and scripts used to create the dimensional data model in the database, with any specific instructions needed to reproduce it.
2. The Python Jupyter Notebook in a dedicated folder in your GitHub repository that contains the dbt models.
3. The `README.md` with the steps needed to test your proposed solution.
4. If you were able to create the report, send us the Power BI semantic model and report, or the Superset report you created.

---

The table headers may be a bit confusing because you do not have full understanding of our language in the logistics business, so do your best to review and make assumptions. Unfortunately, we cannot answer questions about the challenge while you are working on it, but we encourage you to write them down so we can discuss them during the interview review portion.

We hope you enjoy working on this project!

Thank you,
**Loadsmart Team**
