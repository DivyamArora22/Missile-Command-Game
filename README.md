# Text-Mode Missile Command

This project implements a text-mode version of Missile Command, a classic arcade video game, using x86 assembly language as an extension to the Linux real-time clock (RTC) driver. The assignment involves creating a linked list of missiles managed by kernel-space code and implementing user-space code to process user input and update the game.

## Game Overview

In this Missile Command implementation, the player controls a missile silo, aiming to protect cities from enemy missiles. The player can direct missiles by moving the crosshairs and pressing the spacebar to fire. The game ends when enemy missiles destroy all cities. The score is determined by the number of enemy missiles destroyed.

### Implementation Details

#### MP1 Tasklet

The `mp1_rtc_tasklet` function is called on RTC interrupts, updating missile positions, handling explosions, and notifying user-space if the game state changes.

#### MP1 Ioctls

1. **mp1_ioctl_startgame:** Initializes game variables and sets the crosshairs to the screen center.
2. **mp1_ioctl_addmissile:** Adds a new missile to the game, copying user data to kernel space.
3. **mp1_ioctl_movexhairs:** Moves the crosshairs based on user input.
4. **mp1_ioctl_getstatus:** Retrieves the current score and city statuses for the user.
5. **mp1_ioctl_endgame:** Cleans up memory and ends the game.

### Synchronization Constraints

Care is taken to maintain proper synchronization, ensuring that modifications to the linked list are performed safely.

## Usage

For detailed instructions on building, running, and interacting with the Missile Command game, refer to the project documentation.

## License

This project is licensed under [MIT License](LICENSE).

