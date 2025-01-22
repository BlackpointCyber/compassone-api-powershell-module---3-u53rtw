# Pull Request Description

## Summary
<!-- Provide a detailed description of the changes with clear rationale -->


## Related Issue
<!-- Link to related GitHub issue (if applicable) -->
Fixes #

## Type of Change
<!-- Check all that apply -->
- [ ] 🐛 Bug fix
- [ ] ✨ New feature
- [ ] 📚 Documentation update
- [ ] ⚡ Performance improvement
- [ ] ♻️ Code refactoring
- [ ] 🧪 Test update
- [ ] 💥 Breaking change

## Quality Assurance Checklist

### Testing & Analysis
<!-- All items must be checked before review -->
- [ ] ✅ Unit tests added/updated and passing
- [ ] ✅ Integration tests added/updated and passing
- [ ] ✅ Code coverage maintained or improved (>90%)
- [ ] ✅ PSScriptAnalyzer checks passing with zero warnings
- [ ] ✅ Performance impact validated

### Security Review
<!-- All items must be checked before review -->
- [ ] 🔒 Security best practices followed
- [ ] 🔒 No credentials or sensitive data exposed
- [ ] 🔒 Authentication and authorization validated
- [ ] 🔒 Input validation implemented
- [ ] 🔒 Error handling prevents information disclosure

## Documentation Checklist
<!-- All items must be checked before review -->
- [ ] 📝 README.md updated (if applicable)
- [ ] 📝 PowerShell help documentation updated (100% coverage)
- [ ] 📝 Comment-based help added/updated for all functions
- [ ] 📝 Example code and usage updated
- [ ] 📝 CHANGELOG.md updated with changes
- [ ] 📝 Breaking changes documented (if applicable)

## PowerShell Best Practices
<!-- All items must be checked before review -->
- [ ] ✨ Follows PowerShell naming conventions
- [ ] ✨ Uses approved PowerShell verbs
- [ ] ✨ Implements proper error handling
- [ ] ✨ Includes verbose logging
- [ ] ✨ Supports PowerShell pipeline
- [ ] ✨ Implements parameter validation
- [ ] ✨ Follows ShouldProcess pattern (if applicable)

## Additional Notes
<!-- Add any additional notes for reviewers -->


## PR Submission Guidelines
- Ensure all checkboxes above are checked or marked N/A with explanation
- Branch naming should follow pattern: `^(feature|bugfix|hotfix|release)/\w+`
- Squash or rebase commits before merging
- Required reviewers: code owner and security reviewer
- Required checks must pass: unit tests, integration tests, code coverage, security scan
- Minimum 2 approvals required for merge

For detailed contribution guidelines, see [CONTRIBUTING.md](../CONTRIBUTING.md)