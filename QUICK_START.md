# Quick Start Guide for Marc & Frankie

## First Time Setup (Do Once)

1. Accept the GitHub invitation email from Ru

2. Clone the project:
```bash
git clone https://github.com/roobear777/zenmo.git
cd zenmo
```

3. Install Flutter dependencies:
```bash
flutter pub get
```

4. Switch to your branch:
```bash
git checkout marc/starter
# or
git checkout frankie/starter
```

5. Test it works:
```bash
flutter run
```

## Daily Workflow

### Start working:
```bash
git checkout your-name/starter
```

### Make changes, then save them:
```bash
git add .
git commit -m "What you built"
git push
```

### Get Ru's latest updates:
```bash
git checkout main
git pull
git checkout your-name/starter
git merge main
```

## Need Help?

- Stuck? Ask Ru
- Want to create a new feature branch? `git checkout -b your-name/feature-name`
- See what branch you're on: `git branch`

That's it!
