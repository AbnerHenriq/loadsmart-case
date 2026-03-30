{% macro parse_ts(col) %}
    strptime({{ col }}, '%m/%d/%Y %H:%M')::timestamp
{% endmacro %}
