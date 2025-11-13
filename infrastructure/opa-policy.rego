package terraform.plan

# Deny any resource destruction
deny[msg] {
    resource_change := input.resource_changes[_]
    resource_change.change.actions[_] == "delete"
    msg := sprintf("Resource destruction detected: %s (%s) will be deleted", [
        resource_change.address,
        resource_change.type
    ])
}

# Deny any resource replacement that involves deletion
deny[msg] {
    resource_change := input.resource_changes[_]
    "delete" in resource_change.change.actions
    "create" in resource_change.change.actions
    msg := sprintf("Resource replacement detected (will destroy and recreate): %s (%s)", [
        resource_change.address,
        resource_change.type
    ])
}

