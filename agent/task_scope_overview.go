package agent

// taskScopeOverview expands company references so the planner receives the
// domains, networks and advisory keywords associated with the current task.
func (t *ToolSet) taskScopeOverview() []map[string]any {
	rows, err := t.as.ListTaskScope(t.taskID)
	if err != nil {
		return nil
	}
	result := make([]map[string]any, 0, len(rows))
	for _, row := range rows {
		entry := map[string]any{"kind": row.Kind, "source": row.Source, "reason": row.Reason}
		switch {
		case row.Domain != "":
			entry["value"] = row.Domain
		case row.Net != "":
			entry["value"] = row.Net
		case row.Value != "":
			entry["value"] = row.Value
		}
		if row.CompanyID != nil {
			entry["company_id"] = *row.CompanyID
			entry["company_name"] = row.CompanyName
			if t.cs != nil {
				if rules, err := t.cs.GetScope(*row.CompanyID); err == nil {
					scope := make([]map[string]any, 0, len(rules))
					keywords := []string{}
					for _, rule := range rules {
						value := rule.Value
						if rule.Domain != "" {
							value = rule.Domain
						} else if rule.Net != "" {
							value = rule.Net
						}
						// Preserve the user's spelling and host notation in prompt context;
						// normalized fields remain the database's matching authority.
						if rule.Raw != "" {
							value = rule.Raw
						}
						scope = append(scope, map[string]any{"kind": rule.Kind, "value": value})
						if rule.Kind == "keyword" {
							keywords = append(keywords, value)
						}
					}
					entry["company_scope"] = scope
					entry["company_keywords"] = keywords
				}
			}
		}
		result = append(result, entry)
	}
	return result
}
