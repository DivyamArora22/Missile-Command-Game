
# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32
	BASEALIVE = 0x00FFFFFF

	EXPLOSION = 64			#character to draw for an explosion - '@'
	BITSHIFT = 16			#used for shifting bits to access the least or most significant 2 bytes of a register
	YOFFSET = 160			#80 characters per row X 2 bytes per character
	XUPPER = 79				#upper bound of X to be in the screen
	YUPPER = 24				#upper bound of Y to be in the screen
	SPACECHAR = 0x20		#hex character for blank space
	CROSSHAIR = 0x2B		#hex character for +
	XCENTER = 40
	YCENTER = 12

# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score
get_status_value: .long 0x0		#stores the information about bases and score status

# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		call update_missiles
		call redraw_bases 
		call redraw_xhair

		popl %edi
		popl %esi
		popl %ebx

		leave

		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument

# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
    movl 8(%esp), %esi
    cmpl $0, %esi
    jl invalid_cmd
    cmpl $4, %esi
    jg invalid_cmd
    jmp *JUMPTABLE(, %esi, 4)
    ret
    
invalid_cmd:
    movl $-1, %eax        
		ret

JUMPTABLE:
    .long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame


# ----------------- Functions private to this file -------------------

update_missiles:
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	movl mp1_missile_list, %ebx		#move the value of the head pointer to a register

	#THIS IS THE MAIN LOOP TO ITERATE THROUGH ALL MISSILES IN THE LINKED LIST
	list_loop:						
		cmpl $0, %ebx				#check if the missile list is empty
		je finish_update_missile	#if the list is end the update_missile function
									#THE FOLLOWING PART IS TO CALCULATE SCREEN OFFSET FOR DRAWING A CHARACTER
		movl X(%ebx), %ecx			
		shrl $BITSHIFT, %ecx		#extract the most significant 16 bits of X value
		imul $2, %ecx				#multiply X value with 2 bytes per character
		movl Y(%ebx), %edx
		shrl $BITSHIFT, %edx		#extract the most significant 16 bits of Y value
		imul $YOFFSET, %edx				#multiply with Y offset
		addl %ecx, %edx
		movl %edx, %eax
		movb $SPACECHAR, %cl				#draw blank space at old xy location
		push %edx
		call mp1_poke
		pop %edx	

		movl EXPLODED(%ebx), %edx	#check if missile has exploded
		cmpl $0, %edx 
		jne call_explode_missile

		movl X(%ebx), %ecx			#calculate the updated X location by adding VX
		movl VX(%ebx), %edx
		addl %ecx, %edx
		movl %edx, X(%ebx)			#set the updated X location
		shrl $BITSHIFT, %edx

		cmpl $0, %edx				#check X lower bound in screen
		jl remove_missile
		cmpl $XUPPER, %edx			#check X upper bound in screen
		jg remove_missile

		xorl %edx, %edx

		movl Y(%ebx), %ecx			#calculate the updated Y location by adding VX
		movl VY(%ebx), %edx
		addl %ecx, %edx
		movl %edx, Y(%ebx)			#set the updated Y location
		shrl $BITSHIFT, %edx
		
		cmpl $0, %edx				#check Y lower bound in screen
		jl remove_missile
		cmpl $YUPPER, %edx				#check Y upper bound in screen
		jg remove_missile

		movl X(%ebx), %ecx			#check if the X value has reached the destination
		shrl $BITSHIFT, %ecx
		movl DEST_X(%ebx), %edx
		cmpl %ecx, %edx
		jne draw_missile			#if not then skip checking Y and draw missile

		movl Y(%ebx), %ecx			#check if the Y value has reached the destination
		shrl $BITSHIFT, %ecx
		movl DEST_Y(%ebx), %edx
		cmpl %ecx, %edx
		je call_explode_missile		#if reached destination then jump to explode missile subroutine

		draw_missile:				
			movl X(%ebx), %ecx		#THE FOLLOWING PART IS TO CALCULATE SCREEN OFFSET FOR DRAWING A CHARACTER
			shrl $BITSHIFT, %ecx
			imul $2, %ecx
			movl Y(%ebx), %edx
			shrl $BITSHIFT, %edx
			imul $YOFFSET, %edx
			addl %ecx, %edx
			movl %edx, %eax
			movb C(%ebx), %cl		#draw the missile character
			pushl %edx
			call mp1_poke
			popl %edx
			jmp next_loop
		
		call_explode_missile:

			movl X(%ebx), %ecx		#THE FOLLOWING PART IS TO CALCULATE SCREEN OFFSET FOR DRAWING A CHARACTER
			shrl $BITSHIFT, %ecx
			imul $2, %ecx
			movl Y(%ebx), %edx
			shrl $BITSHIFT, %edx
			imul $YOFFSET, %edx
			addl %ecx, %edx
			movl %edx, %eax
			movb $EXPLOSION, %cl	#draw the explosion character
			pushl %edx
			call mp1_poke
			popl %edx
			
			pushl %ebx
			call missile_explode	#call the helper function missile explode
			popl %ebx

			cmpl $0, %eax			#check the return value from the function call
			je dont_notify_user		
			pushl %edx
			pushl %ecx
			call mp1_notify_user	#call notify user if a non zero value is returned
			popl %edx
			popl %ecx

			dont_notify_user:
				movl EXPLODED(%ebx), %esi		#Decrement the exploded counter
				decl %esi
				movl %esi , EXPLODED(%ebx)
				movl EXPLODED(%ebx), %ecx
				cmpl $0, %ecx
				jne next_loop					#erase if counter is zero otherwise go to next missile
				
			erase_explosion:
				movl X(%ebx), %ecx		#THE FOLLOWING PART IS TO CALCULATE SCREEN OFFSET FOR DRAWING A CHARACTER
				shrl $BITSHIFT, %ecx
				imul $2, %ecx
				movl Y(%ebx), %edx
				shrl $BITSHIFT, %edx
				imul $YOFFSET, %edx
				addl %ecx, %edx
				movl %edx, %eax
				movb $SPACECHAR, %cl	#draw empty space character to erase explosion
				pushl %edx
				call mp1_poke
				popl %edx
			


		remove_missile:
			movl mp1_missile_list, %ecx		
			cmpl mp1_missile_list, %ebx
			jne remove_element_loop
		
			remove_head:						#for deleting the node if it is at the head of the list
				movl mp1_missile_list, %esi	
				pushl %esi				
				movl NEXT(%esi), %esi			#load the address of next element in esi
				movl %esi, mp1_missile_list		#set the head of list with esi
				call mp1_free				
				addl $4, %esp					#free memory space and push the stack pointer up to remove the argument by an offset of 4
				movl mp1_missile_list, %ebx
				jmp list_loop				

			remove_element_loop:				#looping through the linked list until the node to be removed is found
				movl NEXT(%ecx), %esi		
				cmpl %esi, %ebx				
				je remove_element
				movl NEXT(%ecx), %ecx 			
				jmp remove_element_loop		

			remove_element:
				movl NEXT(%ebx), %edi 			#load the address of next element
				movl %edi, NEXT(%ecx)			#update the NEXT pointer of previous node to point to the next address
				movl %edi, %ebx					#update ebx to point to the new element before looping back

				pushl %esi
				call mp1_free
				addl $4, %esp					#free memory space and push the stack pointer up to remove the argument by an offset of 4

				jmp list_loop					#loop back when removed

			

		next_loop:
			movl NEXT(%ebx), %ebx
			jmp list_loop
		
		finish_update_missile:
			popl %edi
			popl %esi
			popl %ebx
			leave
			ret
	
	

redraw_bases:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		movl $0, %ebx
		redraw_bases_loop:
			cmpl $3, %ebx			# compare if the loop counter is 3
			je end_redraw_bases
	
			movl %ebx, %esi			#THE FOLLOWING PART IS TO CALCULATE SCREEN OFFSET FOR DRAWING BASES
			addl $1, %esi			
			imul $20, %esi			#Find the center of the base which is at multiple of 20
			subl $2, %esi			#Subtract 2 to get the starting point of making the base
			imul $2, %esi			#Multiply X value with 2 bytes per character
			movl $YUPPER, %edi		#Y value to draw base
			imul $YOFFSET, %edi		#Find Y offset
			addl %edi, %esi
			movl %esi, %eax			#set the offset for drawing bases
			xorl %esi, %esi			

			movzbl base_alive(%ebx), %edx		#move a zero extended byte from base alive to edx using the loop counter offset
			cmpl $0, %edx						#check if base is dead or alive
			je dead_base
		
		alive_base:
			leal base_pic, %edi
			jmp print_base_and_loopback

		dead_base:
			leal dead_base_pic, %edi
			
		print_base_and_loopback:
			movb (%edi,%esi,1), %cl				#loop through the dead_base_pic or base_pic
			pushl %edx
			pushl %edx
			call mp1_poke						
			popl %edx
			popl %edx
			incl %esi
			addl $2, %eax						#add 2 bytes to the character display offset
			cmpl $5, %esi						#check the loop for 5 iterations to print 5 chars
			jb print_base_and_loopback
			addl $1, %ebx						#increment main loop counter
			jmp redraw_bases_loop

		end_redraw_bases:
			popl %edi
			popl %esi
			popl %ebx
			leave
			ret

redraw_xhair:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		movl (crosshairs_x), %esi		#x-crosshair
		movl (crosshairs_y), %edi		#y-crosshair

		pushl %edx						#THE FOLLOWING PART IS TO CALCULATE SCREEN OFFSET FOR DRAWING BASES
		imul $YOFFSET, %edi
		imul $2, %esi
		addl %esi, %edi
		movl %edi, %eax
		movb $CROSSHAIR, %cl			#draw crosshair
		call mp1_poke
		popl %edx
		leave
		ret
#------------------------------------------------------------------------------------------------
#int mp1_ioctl_startgame(unsigned long ignore);
#Initializes the game.
#This function is called at the beginning of the game. 
#It initializes all the variables used by the driver, including those declared in mp1.S.
#Additionally, it sets the crosshairs to the center of the screen at coordinates (40, 12).
#Inputs: 'ignore' (unsigned long) - a parameter that is meaningless and should be ignored.
#Outputs: None 
#Registers: Standard C calling convention
mp1_ioctl_startgame:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		movl $XCENTER, crosshairs_x		#Initialize X and Y crosshair position
		movl $YCENTER, crosshairs_y

		movl $0, mp1_missile_list		#initialze missile list
		movl $0, mp1_score				#reset score
		movl $BASEALIVE, base_alive 	#set basealive values

		popl %edi
		popl %esi
		popl %ebx

		leave
		ret

#------------------------------------------------------------------------------------------------
#int mp1_ioctl_addmissile(struct missile* user_missile);
#Adds a new missile to the game.
#This ioctl function adds a new missile to the game. It receives a pointer to a 'struct missile'
#in user space and copies the user's missile into a dynamically allocated buffer in kernel space.
#If memory allocation or data copy fails, it returns -1 and frees any allocated memory. 
#If successful, it adds the new missile to a linked list and returns 0.
#Inputs: 'user_missile' (struct missile*) - a pointer to the user's missile data.
#Outputs: Returns 0 on success, -1 on failure.
#Registers: Standard C calling convention
mp1_ioctl_addmissile:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		movl 8(%ebp), %ebx		#getting the pointer to missilie list

		empty_check:			#check if missile list is empty
			cmpl $0, %ebx
			je empty_error

		malloc_check:			#allocate memory for 33 bytes of struct missisle
			pushl $33
			call mp1_malloc

			cmpl $0, %eax
			je malloc_error
		
		copy_from_user_check:
			pushl $33					#memory for 33 bytes of struct missile
			pushl 8(%ebp)				#memory address from user
			pushl %eax					#memory address to kernel
			call mp1_copy_from_user
			cmpl $0, %eax
			jne function_error
			popl %eax
			popl 8(%ebp)				#pop the argument which is at the offset of 8 from base pointer

		update_linked_list:
			movl mp1_missile_list, %edx		
			movl %edx, (%eax)			
			movl %eax, mp1_missile_list
			jmp finish

		empty_error:
			movl $-1, %eax
			jmp finish

		malloc_error:
			popl 8(%ebp)		#this subroutine is used to free memory
			pushl %eax			
			call mp1_free
			popl %eax
			movl $-1, %eax		#return -1 as error
			jmp finish

		function_error:
			popl %eax			#this subroutine is used to free memory
			popl 8(%ebp)		
			pushl %eax			
			call mp1_free		
			popl %eax
			movl $-1, %eax		#return -1 as error
			jmp finish
			
		finish:
			popl %edi
			popl %esi
			popl %ebx
			leave
				ret

#------------------------------------------------------------------------------------------------
#int mp1_ioctl_movexhairs(unsigned long xhair_delta_packed);
#This function moves the crosshairs on the screen based on the provided 32-bit integer. 
#It ensures that the crosshairs stay within the screen boundaries (0-79 for x and 0-24 for y)
#and redraws them at the new location.
#Inputs: a 32-bit integer with packed x and y component changes.
#Outputs: Always returns 0.
#Registers: Standard C calling convention
mp1_ioctl_movexhairs:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		movl (crosshairs_x), %esi	#x-crosshair
		movl (crosshairs_y), %edi	#y-crosshair

		pushl %edx					#THE FOLLOWING PART IS TO CALCULATE SCREEN OFFSET FOR DRAWING BLANK SPACE
		imul $YOFFSET, %edi
		imul $2, %esi
		addl %esi, %edi
		movl %edi, %eax
		movb $SPACECHAR, %cl		#draw blank space
		call mp1_poke
		popl %edx
									#find new crosshair location with given arguments
		movl 8(%ebp), %ebx			#load the new x value of the argument which is at an offset of 8 from base pointer
		movswl %bx, %ebx			#store the new x value
		movl 8(%ebp), %ecx			#load the new y value of the argument which is at an offset of 8 from base pointer
		sarl $BITSHIFT, %ecx		#store the new y value

		movl (crosshairs_x), %esi	#x-crosshair
		movl (crosshairs_y), %edi	#y-crosshair
		addl %ebx, %esi
		addl %ecx, %edi

		#check for x edges
		cmpl $0, %esi				#check for x lower bound
		jl fix_x_lower
		cmpl $XUPPER, %esi			#check for x upper bound
		jg fix_x_upper
		jmp check_y

		fix_x_lower:
			movl $0, %esi
			jmp check_y
		
		fix_x_upper:
			movl $XUPPER, %esi
		
		check_y:				
			cmpl $0, %edi			#check for y lower bounds
			jl fix_y_lower
			cmpl $YUPPER, %edi		#check for y upper bounds
			jg fix_y_upper
			jmp redrawing
		
		fix_y_lower:
			movl $0, %edi
			jmp redrawing
		
		fix_y_upper:
			movl $YUPPER, %edi
		
		redrawing:						#THE FOLLOWING PART IS TO CALCULATE SCREEN OFFSET FOR DRAWING CROSSHAIR
			movl %esi, crosshairs_x
			movl %edi, crosshairs_y
			pushl %edx
			imul $YOFFSET, %edi
			imul $2, %esi
			addl %esi, %edi
			movl %edi, %eax
			movb $CROSSHAIR, %cl		#draw crosshair
			call mp1_poke
			popl %edx

		popl %edi
		popl %esi
		popl %ebx
		leave
			ret

#------------------------------------------------------------------------------------------------
#int mp1_ioctl_getstatus(unsigned long* user_status);
#Retrieves game status.
#Allows the user to retrieve the current game score and the status of the three cities. 
#Inputs: 'user_status' (unsigned long*) - a pointer to a 32-bit integer in user space.
#Outputs: Returns 0 on success, -1 on failure.
#Registers: Standard C calling convention
mp1_ioctl_getstatus:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		cmpl $0, 8(%ebp)			#check the argument passed for null value
		je getstatus_fail

		xorl %ecx, %ecx				
		movl $2, %ebx				#ebx stores the counter for the loop which is supposed to run 3 times
		get_bases_loop:
			cmpl $0, %ebx			
			jl base_register_set
			shll $1, %ecx			#shift left every time after storing the base status
			movzbl base_alive(%ebx), %esi		#move a zero extended byte from base alive to edx using the loop counter offset
			cmpl $0, %esi			#set the bit 0 if base is dead
			je set_zero
			orl $1, %ecx			#set the bit 1 if base is alive
			set_zero:
				orl $0, %ecx

			decl %ebx				#decrement loop counter
			jmp get_bases_loop
		
		base_register_set:
			shll $BITSHIFT, %ecx	#shift left by 16 to clear the 16 least significant bits
			addl mp1_score, %cx		#put mp1 score in least significant bits

			movl %ecx, get_status_value		#set the value in a global variable
			
			pushl $4					#create space of 4 bytes on stack 
			pushl $get_status_value		#push the status value	
			pushl 8(%ebp)				#push the function argument
			call mp1_copy_to_user
			add $12, %esp				#reset stack pointer by an offset of 12
			cmpl $0, %eax
			jne getstatus_fail
			jmp getstatus_pass

		getstatus_fail:
			movl $-1, %eax			#return -1 for failure
			popl %edx
			popl %edi
			popl %esi
			leave
				ret
		getstatus_pass:
			movl $0, %eax			#return 0 for success
			popl %edi
			popl %esi
			popl %ebx
			leave
				ret

#------------------------------------------------------------------------------------------------
#int mp1_ioctl_endgame(unsigned long ignore);
#Cleans up after the game ends.
#Called when the game is over, this function performs cleanup work. It frees all memory used by
#the linked list of missiles and returns success.
#Inputs: 'ignore' (unsigned long) - should be ignored.
#Outputs: None
#Registers: Standard C calling convention
mp1_ioctl_endgame:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
	
		movl mp1_missile_list, %ebx                 
		
		clear_linked_list:
			cmpl $0, %ebx				#check if the list is empty               
			je end
			pushl NEXT(%ebx) 			#Push the address of the next node onto stack                          		
			pushl %ebx					#Push current node onto stack
			call mp1_free                               
			addl $4, %esp				#pop the argument in stack by moving stack pointer by 4
			popl %ebx
			jmp clear_linked_list
			
		end:
			movl $0, %eax                               
			popl %edi
			popl %esi
			popl %ebx
			leave
				ret
