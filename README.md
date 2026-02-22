# Zenmo

A Flutter application built collaboratively by Ru, Marc, and Frankie.

## Team Workflow

### Branch Structure
- `main` - Production-ready code (protected, Ru has merge control)
- `marc/feature-name` - Marc's feature branches
- `frankie/feature-name` - Frankie's feature branches
- `ru/feature-name` - Ru's feature branches

### Getting Started

1. Clone the repository:
```bash
git clone <repository-url>
cd zenmo
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

### Development Workflow

**For Marc and Frankie:**

1. Create your feature branch:
```bash
git checkout -b marc/your-feature-name
# or
git checkout -b frankie/your-feature-name
```

2. Make your changes and commit:
```bash
git add .
git commit -m "Description of your changes"
```

3. Push your branch:
```bash
git push origin marc/your-feature-name
```

4. Create a Pull Request on GitHub/GitLab for Ru to review

**For Ru:**
- Review pull requests from Marc and Frankie
- Merge approved changes into `main`
- Handle releases and production deployments

## Project Structure

```
zenmo/
├── lib/
│   └── main.dart          # Main application entry point
├── test/                  # Unit and widget tests
├── android/              # Android-specific code
├── ios/                  # iOS-specific code
└── pubspec.yaml          # Dependencies and project config
```

## Next Steps

1. Create a repository on GitHub or GitLab
2. Add remote: `git remote add origin <your-repo-url>`
3. Push initial code: `git push -u origin main`
4. Invite Marc and Frankie as collaborators
5. Set up branch protection rules for `main` branch
