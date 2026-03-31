{% macro parse_ts(col) %}
    STRPTIME({{ col }}, '%m/%d/%Y %H:%M')::TIMESTAMP
{% endmacro %}
