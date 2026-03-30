# Analytics Engineer Challenge
## Data Enablement Team — Loadsmart

---

Olá! Obrigado pelo seu interesse na Loadsmart. Agradecemos seu interesse em nossa empresa e ficamos animados que você decidiu avançar para esta etapa! Esperamos que você ache o desafio estimulante e divertido, e estamos ansiosos para conversar com você sobre os resultados!

O desafio nos permitirá conhecer melhor suas habilidades técnicas. Usaremos seus resultados junto com outras dimensões ao considerar sua adequação para a posição. Este não é o único fator que consideraremos em relação à sua candidatura. Se, por qualquer motivo, você não conseguir completar o desafio inteiro, qualquer progresso que você fizer será levado em consideração no quadro mais amplo. Por favor, avance o máximo que puder e passaremos pelo Q&A na entrevista técnica.

Você terá até sete dias para completar o desafio e nos enviar de volta. **Certifique-se de ter confirmado a data de entrega com o representante que lhe enviou o desafio.**

Após concluir o desafio, envie o link do seu repositório GitHub por e-mail ao representante que o enviou, contendo o `README.md` com os passos necessários para testar sua solução proposta. Por favor, coloque no assunto do e-mail **"SEU NOME COMPLETO - Analytics Engineer Challenge"**.

Boa sorte e divirta-se!

---

Anexamos um conjunto de dados para você trabalhar. **Por favor, procure o arquivo CSV anexado ao e-mail. Aqui está o que pedimos que você faça:**

---

## 1. Dimensional modeling, SQL e habilidades dbt

**a. Ingerir os dados e construir um modelo de dados dimensional (Star Schema):** use o **dbt (data build tool)** e um banco de dados compatível para demonstrar seu modelo de dados. Isso garantirá que a análise de dados esteja disponível via SQL.

---

## 2. Habilidades Python

**a. Funções Python:** por favor, crie uma ou mais das seguintes funções Python em um Jupyter Notebook:

**i. Criar uma função Python para dividir a coluna lane:** crie uma função que receberá um valor de lane e o dividirá em 4 novas colunas: `pickup_city`, `pickup_state`, `delivery_city` e `delivery_state`.

**ii. Criar uma função Python para enviar um arquivo CSV por e-mail:** crie uma função para enviar um arquivo CSV para um e-mail. A função Python deve receber um caminho de arquivo CSV, o assunto do e-mail e um corpo de e-mail.

**iii. Criar uma função Python para enviar um arquivo CSV via sFTP:** crie uma função para enviar um arquivo CSV para um sFTP. A função Python deve receber um caminho de arquivo CSV e o caminho do arquivo de destino.

**b. Exportar um arquivo CSV usando um script Python:** por favor, use o mesmo Jupyter Notebook criado acima para escrever um script Python que lerá seu modelo dimensional e criará uma exportação para um arquivo CSV. Este arquivo deve conter a lista de `loadsmart_ids` que foram entregues no último mês disponível nos dados CSV brutos que enviamos a você. Abaixo está a lista de colunas que precisam estar no arquivo CSV exportado:

| # | Coluna |
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

Se você tiver a capacidade de criar relatórios, por favor tente realizar este último requisito:

## 3. Visualização de dados

**a. Criar um relatório usando os dados modelados:** forneça uma análise visual para que você possa fazer uma prova de conceito de como seu modelo de dados funciona e como podemos utilizá-lo. Você pode usar o Power BI Desktop ou o Superset.

---

## Entregas no repositório GitHub

1. O projeto dbt e os scripts usados para criar o modelo de dados dimensional no banco de dados, com quaisquer instruções específicas necessárias para reproduzi-lo.
2. O Jupyter Notebook Python em uma pasta específica no seu repositório GitHub que contém os modelos dbt.
3. O arquivo `README.md` com os passos necessários para testar sua solução proposta.
4. Se você conseguiu criar o relatório, envie-nos o modelo semântico e relatório do Power BI ou o relatório do Superset que você criou.

---

Os cabeçalhos da tabela podem ser um pouco confusos, pois você não tem um entendimento completo de nossa linguagem no negócio de logística, portanto, faça o seu melhor para revisar e fazer suposições. Infelizmente, não poderemos responder perguntas sobre o desafio enquanto você o estiver fazendo, mas encorajamos você a anotá-las para que possamos discutir durante a parte de revisão da entrevista.

Esperamos que você aprecie trabalhar neste projeto!

Obrigado,
**Loadsmart Team**