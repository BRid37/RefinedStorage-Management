# RS Manager - Refined Storage Management System

A comprehensive Refined Storage management program for CC:Tweaked computers with Advanced Peripherals RS Bridge integration.

## Compatibility

- **CC:Tweaked**: 1.116.2+
- **Advanced Peripherals**: 0.7.57b+
- **Minecraft**: 1.21.1

## Features

### Dashboard
- Real-time energy monitoring with visual progress bar
- Total item count and unique item types
- Active crafting jobs display
- Stock Keeper status and low stock alerts

### Item Search
- Search items by name or display name
- Scrollable results with item counts
- Fast fuzzy matching

### Stock Keeper (Auto-Crafting)
- Define items to keep in stock with target amounts
- Automatic crafting requests when items fall below target
- Priority-based crafting queue
- Visual status indicators (green=OK, orange=low, red=critical)
- Enable/disable individual items or the entire system
- Persistent configuration saved to file

### Crafting Queue
- View all active crafting tasks
- Request new crafts directly from the interface
- Search craftable items

### System Statistics
- Detailed energy statistics (stored, max, usage)
- Storage statistics (total items, unique types)
- Fluid storage overview

### External Monitor Support
- Automatic detection of attached monitors
- Displays system overview on external monitor
- Configurable text scale
- Low stock alerts visible at a glance

### Settings
- Configurable refresh rate
- Auto-craft delay timing
- Low stock threshold percentage
- Monitor settings

## Installation

### Method 1: Pastebin (Recommended)

On your CC:Tweaked computer, run:
```
pastebin run S9vrZ1d0
```

### Method 2: GitHub Direct

1. Fork this repository or upload to your own GitHub
2. Update `GITHUB_USER` in `install.lua` to your username
3. Upload `install.lua` to Pastebin
4. Run the installer

### Method 3: Manual Installation

1. Download all files to your computer
2. Place them in `/rsmanager/` directory:
   ```
   /rsmanager/
   ├── rsmanager.lua
   ├── lib/
   │   ├── config.lua
   │   ├── rsbridge.lua
   │   ├── stockkeeper.lua
   │   ├── monitor.lua
   │   ├── gui.lua
   │   └── utils.lua
   └── config/
       ├── settings.lua
       └── stocklist.lua
   ```
3. Run: `rsmanager`

## Usage

### Starting the Program
```
rsmanager
```
Or reboot to auto-start (if installed via installer).

### Navigation
- **Arrow Keys**: Navigate menus
- **Enter**: Select option
- **Q**: Back/Quit
- **R**: Refresh (in most views)

### Stock Keeper Controls
- **T**: Toggle Stock Keeper on/off
- **A**: Add new item to track
- **E**: Edit selected item
- **D**: Delete selected item
- **C**: Craft selected item immediately
- **S**: Save configuration

### Adding Items to Stock Keeper
1. Navigate to Stock Keeper
2. Press **A** to add
3. Search for the item
4. Select with arrow keys and Enter
5. Set target amount
6. Press Enter to confirm

## File Structure

```
/rsmanager/
├── rsmanager.lua          # Main program
├── lib/
│   ├── config.lua         # Configuration management
│   ├── rsbridge.lua       # RS Bridge API wrapper
│   ├── stockkeeper.lua    # Stock keeping logic
│   ├── monitor.lua        # External monitor display
│   ├── gui.lua            # Terminal UI components
│   └── utils.lua          # Utility functions
├── config/
│   ├── settings.lua       # User settings
│   └── stocklist.lua      # Stock keeper item list
└── logs/
    └── rsmanager.log      # Application logs
```

## Configuration

### settings.lua
```lua
{
    refreshRate = 5,        -- Dashboard refresh rate (seconds)
    craftDelay = 10,        -- Stock keeper check interval (seconds)
    lowStockPercent = 50,   -- Low stock warning threshold (%)
    useMonitor = true,      -- Enable external monitor
    monitorScale = 1,       -- Monitor text scale (0.5-2)
    stockKeeperEnabled = true,
    maxCraftingJobs = 5,
}
```

### stocklist.lua
```lua
{
    items = {
        {
            name = "minecraft:iron_ingot",
            amount = 256,
            displayName = "Iron Ingot",
            priority = 1,
            enabled = true
        },
        -- More items...
    },
    enabled = true,
}
```

## RS Bridge API Reference

The program uses the following RS Bridge methods from Advanced Peripherals:

| Method | Description |
|--------|-------------|
| `getEnergyStorage()` | Get current energy stored |
| `getMaxEnergyStorage()` | Get maximum energy capacity |
| `getEnergyUsage()` | Get current energy usage per tick |
| `listItems()` | List all items in the system |
| `getItem({name=...})` | Get specific item details |
| `listFluids()` | List all fluids in the system |
| `listCraftableItems()` | List all craftable items |
| `isItemCraftable({name=...})` | Check if item can be crafted |
| `craftItem({name=..., count=...})` | Request item craft |
| `getCraftingTasks()` | Get active crafting tasks |

## Troubleshooting

### "No RS Bridge found"
- Ensure an RS Bridge from Advanced Peripherals is placed adjacent to the computer
- The RS Bridge must be connected to your RS network

### Downloads fail during installation
- Check that HTTP is enabled in CC:Tweaked config
- Verify your GitHub username is correct in the installer
- Ensure the repository is public

### Stock Keeper not crafting
- Verify the item has an autocrafting pattern in your RS system
- Check that the RS system has enough energy
- Ensure Stock Keeper is enabled (not paused)

### External monitor not working
- Place a monitor adjacent to the computer
- Enable "useMonitor" in settings
- Try adjusting monitorScale if text is too large/small

## License

MIT License - See LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Credits

- Built for CC:Tweaked and Advanced Peripherals
- Inspired by various RS automation projects in the community
